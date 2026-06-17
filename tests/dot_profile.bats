setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export DOTFILES="$REPO"
  export TERM=dumb
  DOT_PROFILE="$REPO/bin/dot-profile"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "get defaults to personal" {
  run "$DOT_PROFILE" get
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "set work then get returns work" {
  run "$DOT_PROFILE" set work
  [ "$status" -eq 0 ]
  run "$DOT_PROFILE" get
  [ "$output" = "work" ]
}

@test "set rejects an invalid profile" {
  run "$DOT_PROFILE" set bogus
  [ "$status" -ne 0 ]
}

@test "set-config and show surface the value" {
  "$DOT_PROFILE" set work
  "$DOT_PROFILE" set-config work_dir "$HOME/work"
  run "$DOT_PROFILE" show
  [ "$status" -eq 0 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"work_dir="* ]]
  [[ "$output" == *"$HOME/work"* ]]
  [[ "$output" == *"work_dir=$HOME/work"* ]]
}

@test "set-config requires both key and value" {
  run "$DOT_PROFILE" set-config work_dir
  [ "$status" -ne 0 ]
}

@test "set with no argument exits non-zero" {
  run "$DOT_PROFILE" set
  [ "$status" -ne 0 ]
}

@test "--help exits 0" {
  run "$DOT_PROFILE" --help
  [ "$status" -eq 0 ]
}

@test "unknown subcommand exits non-zero" {
  run "$DOT_PROFILE" frobnicate
  [ "$status" -ne 0 ]
}
