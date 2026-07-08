setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export SANDBOX
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export DOTFILES="$REPO"
  export TERM=dumb
  mkdir -p "$HOME"
  DOT_MACOS="$REPO/bin/dot-macos"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "dot-macos has a Description line for auto-discovery" {
  run sed -n '2p' "$DOT_MACOS"
  [[ "$output" == "# Description:"* ]]
}

@test "sourcing dot-macos does not execute main (guard is effective)" {
  run bash -c "source '$DOT_MACOS'; echo sourced-ok"
  [ "$status" -eq 0 ]
  [ "$output" = "sourced-ok" ]
}

@test "no subcommand shows usage and exits 0" {
  run "$DOT_MACOS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "--help exits 0 and documents the defaults subcommand" {
  run "$DOT_MACOS" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"defaults"* ]]
}

@test "an unknown subcommand is rejected" {
  run "$DOT_MACOS" frobnicate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown legacy command"* ]]
}

# The `defaults` subcommand mutates real machine state (defaults write, chflags,
# killall) — out of scope to exercise for real (per #50). Confirm only that it's
# gated behind a Darwin check, by sourcing the (guarded) script and reading the
# function body rather than calling it.
@test "setup_macos is gated behind a Darwin check before any defaults write" {
  run bash -c "source '$DOT_MACOS'; declare -f setup_macos"
  [ "$status" -eq 0 ]
  [[ "$output" == *'uname'* ]]
  [[ "$output" == *"Darwin"* ]]
}
