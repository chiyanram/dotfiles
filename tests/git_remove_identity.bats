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
  mkdir -p "$HOME/.ssh"
  # Throwaway passphrase-less keys so tests never hit an interactive prompt.
  ssh-keygen -t ed25519 -N "" -C "seed@test" -f "$HOME/seedkey" >/dev/null 2>&1
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Create a slot whose key is the MANAGED default path (~/.ssh/id_ed25519_<name>):
# pre-seed the key so add-identity reuses it (no interactive keygen prompt).
add_managed_slot() {
  local name="$1" email="$2"
  ssh-keygen -t ed25519 -N "" -C "$name@test" -f "$HOME/.ssh/id_ed25519_$name" >/dev/null 2>&1
  "$REPO/bin/dot-git" add-identity --name "$name" --host github.com --email "$email"
}

@test "remove-identity tears down all artifacts and leaves a sibling slot intact" {
  add_managed_slot ee me@work.test
  # A second, independent slot (adopted external key) that must survive intact.
  "$REPO/bin/dot-git" add-identity --name pers --host github.com \
    --email me@home2.test --key "$HOME/seedkey"

  run "$REPO/bin/dot-git" remove-identity ee
  [ "$status" -eq 0 ]

  # ssh alias block: ee gone, pers intact
  run cat "$HOME/.ssh/config"
  [[ "$output" != *"Host github.com-ee"* ]]
  [[ "$output" == *"Host github.com-pers"* ]]

  # fragment file: ee gone, pers intact
  [ ! -f "$HOME/.gitconfig-ee" ]
  [ -f "$HOME/.gitconfig-pers" ]

  # hasconfig include: ee gone, pers intact
  run cat "$HOME/.gitconfig-identities"
  [[ "$output" != *"git@github.com-ee:"* ]]
  [[ "$output" != *"path = ~/.gitconfig-ee"* ]]
  [[ "$output" == *"git@github.com-pers:"* ]]
  [[ "$output" == *"path = ~/.gitconfig-pers"* ]]

  # allowed_signers: ee line gone, pers line intact
  run cat "$HOME/.local/state/dot/git/allowed_signers"
  [[ "$output" != *"me@work.test "* ]]
  [[ "$output" == *"me@home2.test "* ]]

  # managed key pair for ee is deleted; pers's adopted key is untouched
  [ ! -f "$HOME/.ssh/id_ed25519_ee" ]
  [ ! -f "$HOME/.ssh/id_ed25519_ee.pub" ]
  [ -f "$HOME/seedkey" ]
  [ -f "$HOME/seedkey.pub" ]
}

@test "remove-identity does NOT delete an adopted external key, and warns about it" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  run "$REPO/bin/dot-git" remove-identity ee
  [ "$status" -eq 0 ]

  # config torn down ...
  [ ! -f "$HOME/.gitconfig-ee" ]
  run cat "$HOME/.ssh/config"
  [[ "$output" != *"Host github.com-ee"* ]]

  # ... but the external key is preserved and the user is warned about it
  [ -f "$HOME/seedkey" ]
  [ -f "$HOME/seedkey.pub" ]
  [[ "$output" == *"seedkey"* ]] || true # (output captured below)
  run "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"
  run "$REPO/bin/dot-git" remove-identity ee
  [[ "$output" == *"$HOME/seedkey"* ]]
  [[ "$output" == *"adopted"* || "$output" == *"external"* ]]
}

@test "remove-identity on a non-existent slot errors and changes nothing" {
  add_managed_slot ee me@work.test

  # snapshot the artifacts we expect to survive
  local before_config before_ids
  before_config="$(cat "$HOME/.ssh/config")"
  before_ids="$(cat "$HOME/.gitconfig-identities")"

  run "$REPO/bin/dot-git" remove-identity ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"ghost"* ]]

  # the existing slot is fully intact
  [ -f "$HOME/.gitconfig-ee" ]
  [ -f "$HOME/.ssh/id_ed25519_ee" ]
  [ "$(cat "$HOME/.ssh/config")" = "$before_config" ]
  [ "$(cat "$HOME/.gitconfig-identities")" = "$before_ids" ]
}

@test "remove-identity requires a slot argument" {
  run "$REPO/bin/dot-git" remove-identity
  [ "$status" -ne 0 ]
}

@test "remove-identity warns about local repos still using the alias" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  # A repo under a conventional audit root ($HOME/work) whose origin still uses the alias.
  mkdir -p "$HOME/work/lingering"
  git -C "$HOME/work/lingering" init -q
  git -C "$HOME/work/lingering" remote add origin "git@github.com-ee:owner/repo.git"

  run "$REPO/bin/dot-git" remove-identity ee
  [ "$status" -eq 0 ]
  [[ "$output" == *"lingering"* ]]
  [[ "$output" == *"github.com-ee"* ]]
}

@test "remove-identity reminds the user to revoke the key on the account" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  run "$REPO/bin/dot-git" remove-identity ee
  [ "$status" -eq 0 ]
  [[ "$output" == *"github.com"* ]]
  [[ "$output" == *"revoke"* || "$output" == *"remove"* ]]
}
