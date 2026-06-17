setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "doctor shows the active profile and resolved docker runtime" {
  [[ "$(uname)" == "Darwin" ]] || skip "dot doctor inspection is macOS-only"
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$REPO" TERM=dumb
  "$REPO/bin/dot-profile" set work
  # doctor exits non-zero in a sandbox (missing links/tools) — ignore that; check output.
  run "$REPO/bin/dot-doctor"
  [[ "$output" == *"Profile"* ]]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"rancher"* ]]
}

@test "doctor defaults to the personal profile and docker-desktop runtime" {
  [[ "$(uname)" == "Darwin" ]] || skip "dot doctor inspection is macOS-only"
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$REPO" TERM=dumb
  run "$REPO/bin/dot-doctor"
  [[ "$output" == *"personal"* ]]
  [[ "$output" == *"docker-desktop"* ]]
}
