setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export SANDBOX
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export DOTFILES="$REPO"
  export TERM=dumb
  mkdir -p "$HOME"
  DOT_SHELL="$REPO/bin/dot-shell"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "dot-shell has a Description line for auto-discovery" {
  run sed -n '2p' "$DOT_SHELL"
  [[ "$output" == "# Description:"* ]]
}

@test "sourcing dot-shell does not execute main (guard is effective)" {
  run bash -c "source '$DOT_SHELL'; echo sourced-ok"
  [ "$status" -eq 0 ]
  [ "$output" = "sourced-ok" ]
}

@test "no subcommand shows usage and exits 0" {
  run "$DOT_SHELL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "--help exits 0 and documents change and terminfo" {
  run "$DOT_SHELL" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"change"* ]]
  [[ "$output" == *"terminfo"* ]]
}

@test "an unknown subcommand is rejected" {
  run "$DOT_SHELL" frobnicate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown"* ]]
}

@test "terminfo installs the tmux and italic xterm terminfo into a sandboxed HOME" {
  command -v tic >/dev/null || skip "tic not installed"
  run "$DOT_SHELL" terminfo
  [ "$status" -eq 0 ]
  [[ "$output" == *"terminfo files added"* ]]
  # tic -x installs under the (sandboxed) HOME, never touches the real machine.
  [[ -d "$HOME/.terminfo" ]]
}
