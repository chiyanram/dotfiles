setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks so include paths match
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
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
