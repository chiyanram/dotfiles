setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks so include paths match
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  unset XDG_STATE_HOME # force the code's $HOME/.local/state fallback, not the real machine's
  export DOTFILES="$REPO"
  export TERM=dumb
  # Make git use a clean global config (the committed one) under XDG.
  export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
  mkdir -p "$XDG_CONFIG_HOME/git"
  cp "$REPO/config/git/config" "$GIT_CONFIG_GLOBAL"
  # Personal identity is the unconditional fallback (applies everywhere by default).
  git config -f "$HOME/.gitconfig-local" user.email "me@home.test"
  git config -f "$HOME/.gitconfig-local" user.name "Me Personal"
  # Pre-generate a throwaway passphrase-less key so tests never hit an interactive prompt.
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -C "seed@test" -f "$HOME/seedkey" >/dev/null 2>&1
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "add-identity creates ssh alias block, fragment, and hasconfig include" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --github-user workuser --key "$HOME/seedkey"

  # SSH alias block
  run cat "$HOME/.ssh/config"
  [[ "$output" == *"Host github.com-ee"* ]]
  [[ "$output" == *"HostName github.com"* ]]
  [[ "$output" == *"IdentityFile $HOME/seedkey"* ]]
  [[ "$output" == *"IdentitiesOnly yes"* ]]
  [[ "$output" == *"AddKeysToAgent yes"* ]]
  [[ "$output" == *"UseKeychain yes"* ]]

  # Per-slot fragment
  run git config -f "$HOME/.gitconfig-ee" user.email
  [ "$output" = "me@work.test" ]
  run git config -f "$HOME/.gitconfig-ee" github.user
  [ "$output" = "workuser" ]

  # hasconfig include line
  run cat "$HOME/.gitconfig-identities"
  [[ "$output" == *'hasconfig:remote.*.url:git@github.com-ee:*/**'* ]]
  [[ "$output" == *"path = ~/.gitconfig-ee"* ]]
}

@test "add-identity omits github.user when --github-user is not passed" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  run git config -f "$HOME/.gitconfig-ee" user.email
  [ "$output" = "me@work.test" ]
  run git config -f "$HOME/.gitconfig-ee" github.user
  [ "$status" -ne 0 ]
}

@test "add-identity prints the public key to register" {
  run "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ssh-ed25519 "* ]]
}

@test "email binds to the slot when the remote uses the alias, fallback otherwise" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  mkdir -p "$HOME/bound" "$HOME/unbound"
  git -C "$HOME/bound" init -q
  git -C "$HOME/bound" remote add origin "git@github.com-ee:owner/repo.git"
  git -C "$HOME/unbound" init -q
  git -C "$HOME/unbound" remote add origin "git@github.com:owner/repo.git"

  run git -C "$HOME/bound" config user.email
  [ "$output" = "me@work.test" ]
  run git -C "$HOME/unbound" config user.email
  [ "$output" = "me@home.test" ]
}

@test "add-identity is idempotent — re-run does not duplicate blocks" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  run bash -c "grep -c '^Host github.com-ee\$' '$HOME/.ssh/config'"
  [ "$output" -eq 1 ]
  run bash -c "grep -c 'hasconfig:remote.\\*.url:git@github.com-ee:' '$HOME/.gitconfig-identities'"
  [ "$output" -eq 1 ]
}

@test "add-identity requires --name, --host, and --email" {
  run "$REPO/bin/dot-git" add-identity --host github.com --email e@work.test --key "$HOME/seedkey"
  [ "$status" -ne 0 ]
  [[ "$output" == *"required"* ]]

  run "$REPO/bin/dot-git" add-identity --name ee --email e@work.test --key "$HOME/seedkey"
  [ "$status" -ne 0 ]

  run "$REPO/bin/dot-git" add-identity --name ee --host github.com --key "$HOME/seedkey"
  [ "$status" -ne 0 ]
}

@test "add-identity rejects an unknown flag" {
  run "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email e@work.test --bogus x --key "$HOME/seedkey"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown argument"* ]]
}

@test "add-identity errors when --key path does not exist" {
  run "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email e@work.test --key "$HOME/nope"
  [ "$status" -ne 0 ]
}

@test "the retired work-identity command no longer exists" {
  run "$REPO/bin/dot-git" work-identity --name N --email e@work.test
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown"* ]]
}

@test "add-identity writes SSH signing config into the slot fragment" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  run git config -f "$HOME/.gitconfig-ee" gpg.format
  [ "$output" = "ssh" ]
  run git config -f "$HOME/.gitconfig-ee" user.signingkey
  [ "$output" = "$HOME/seedkey.pub" ]
  run git config -f "$HOME/.gitconfig-ee" commit.gpgsign
  [ "$output" = "true" ]
  run git config -f "$HOME/.gitconfig-ee" tag.gpgsign
  [ "$output" = "true" ]

  # Allowed-signers gains an <email> <keytype> <keydata> line for the slot.
  run cat "$HOME/.local/state/dot/git/allowed_signers"
  [[ "$output" == *"me@work.test ssh-ed25519 "* ]]
}

@test "round-trip: a commit under the slot is SSH-signed and verifies against the slot key" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  mkdir -p "$HOME/bound"
  git -C "$HOME/bound" init -q
  git -C "$HOME/bound" remote add origin "git@github.com-ee:owner/repo.git"

  # Fragment is active (remote uses the alias), so the commit is signed by the slot key.
  git -C "$HOME/bound" commit -q --allow-empty -m "signed under ee"

  run git -C "$HOME/bound" config user.email
  [ "$output" = "me@work.test" ]

  run git -C "$HOME/bound" verify-commit HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"Good \"git\" signature for me@work.test"* ]]

  run git -C "$HOME/bound" log --show-signature -1
  [[ "$output" == *"Good \"git\" signature for me@work.test"* ]]
}

@test "negative: a commit signed by a different slot's key does not verify as this slot" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"
  # A second slot with its own key/email — its key is a valid signer, but bound to a
  # DIFFERENT principal in allowed_signers.
  ssh-keygen -t ed25519 -N "" -C "other@test" -f "$HOME/otherkey" >/dev/null 2>&1
  "$REPO/bin/dot-git" add-identity --name pers --host github.com \
    --email me@home2.test --key "$HOME/otherkey"

  mkdir -p "$HOME/bound"
  git -C "$HOME/bound" init -q
  git -C "$HOME/bound" remote add origin "git@github.com-ee:owner/repo.git"
  # Sign as the ee identity's email but with the WRONG (pers) key.
  git -C "$HOME/bound" config user.signingkey "$HOME/otherkey.pub"
  git -C "$HOME/bound" commit -q --allow-empty -m "mis-signed"

  # committer email is still me@work.test (ee fragment) ...
  run git -C "$HOME/bound" config user.email
  [ "$output" = "me@work.test" ]
  # ... but allowed_signers binds me@work.test to the ee key. The otherkey signature
  # can never verify AS the ee identity: it is attributed to the pers principal that
  # owns that key, so a forged ee commit is impossible.
  run git -C "$HOME/bound" verify-commit HEAD
  [[ "$output" != *'Good "git" signature for me@work.test'* ]]
  [[ "$output" == *"me@home2.test"* ]]
}

@test "add-identity is idempotent — re-run does not duplicate signing artifacts" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  run bash -c "grep -c 'me@work.test ssh-ed25519' '$HOME/.local/state/dot/git/allowed_signers'"
  [ "$output" -eq 1 ]
  # Fragment keys are single-valued (git config replaces, not appends).
  run bash -c "grep -c 'gpgsign = true' '$HOME/.gitconfig-ee'"
  [ "$output" -eq 2 ] # commit.gpgsign + tag.gpgsign, one each
}

@test "add-identity guidance says register the key as both Authentication and Signing" {
  run "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Authentication"* ]]
  [[ "$output" == *"Signing"* ]]
}
