setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX"
  export TERM=dumb
  source "$REPO/bin/lib/git-slots.sh"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "git_slot_ghuser reads github.user from the slot fragment" {
  git config -f "$HOME/.gitconfig-ee" github.user "workuser"
  run git_slot_ghuser ee
  [ "$status" -eq 0 ]
  [ "$output" = "workuser" ]
}

@test "git_slot_ghuser fails when github.user is unset in an existing fragment" {
  git config -f "$HOME/.gitconfig-ee" user.email "me@work.test"
  run git_slot_ghuser ee
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "git_slot_ghuser fails when the slot fragment doesn't exist" {
  run git_slot_ghuser nonexistent
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
