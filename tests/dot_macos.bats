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

# #174: the guard uses `return 1`, not `exit 1`, per the repo's function rule.
# `return` only propagates because setup_macos is the last command of its case
# arm — so assert the observable status, not the keyword. `defaults` and
# `killall` are stubbed as well: if the guard ever regresses, the test must not
# mutate the real machine to find out.
@test "on a non-Darwin system the defaults subcommand fails without writing" {
  local stub="$SANDBOX/stub"
  mkdir -p "$stub"
  printf '#!/bin/sh\necho Linux\n' >"$stub/uname"
  printf '#!/bin/sh\necho "STUB-DEFAULTS $*" >>"%s/called"\n' "$stub" >"$stub/defaults"
  printf '#!/bin/sh\nexit 0\n' >"$stub/killall"
  chmod +x "$stub/uname" "$stub/defaults" "$stub/killall"

  PATH="$stub:$PATH" run "$DOT_MACOS" defaults
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-macOS"* ]]
  [ ! -f "$stub/called" ]
}

# #172: tap-to-click only wrote the Bluetooth domain, so it was a no-op on the
# built-in trackpad. All three writes are needed — the second for the built-in
# device, the third for the System Settings checkbox that mirrors it.
@test "tap to click writes the built-in trackpad domain, not just Bluetooth" {
  run bash -c "source '$DOT_MACOS'; declare -f setup_macos"
  [ "$status" -eq 0 ]
  [[ "$output" == *"com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking"* ]]
  [[ "$output" == *"com.apple.AppleMultitouchTrackpad Clicking"* ]]
  [[ "$output" == *"com.apple.mouse.tapBehavior"* ]]
}

# #172: nothing setup_macos writes affects Safari or Mail, and killing them
# discards unsaved tabs and drafts. Assert against the loop line alone — the
# whole function body mentions both apps in a comment, and a bare substring
# match would also false-fail on an unrelated word like "Mailbox".
@test "the killall list restarts only Finder, Dock and SystemUIServer" {
  run bash -c "source '$DOT_MACOS'; declare -f setup_macos"
  [ "$status" -eq 0 ]
  killall_line="$(printf '%s\n' "$output" | grep 'for app in')"
  [[ "$killall_line" == *"Finder Dock SystemUIServer"* ]]
  [[ "$killall_line" != *"Safari"* ]]
  [[ "$killall_line" != *"Mail"* ]]
}

# killall exits 1 when an app isn't running. Without `|| true`, `set -e` aborts
# the script there: the logout warning never prints and the command reports
# failure after every setting has already been applied.
# declare -f pretty-prints the loop over several lines, so the guard lands on
# the killall line rather than the `for` line.
@test "the killall loop tolerates an app that is not running" {
  run bash -c "source '$DOT_MACOS'; declare -f setup_macos"
  [ "$status" -eq 0 ]
  killall_cmd="$(printf '%s\n' "$output" | grep 'killall')"
  [[ "$killall_cmd" == *"|| true"* ]]
}
