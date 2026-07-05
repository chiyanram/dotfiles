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

@test "doctor runs under system bash 3.2 without the associative-array crash" {
  [[ "$(uname)" == "Darwin" ]] || skip "system bash 3.2 is macOS-only"
  [[ -x /bin/bash ]] || skip "no /bin/bash"
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$REPO" TERM=dumb
  # A fresh Mac runs doctor under bash 3.2. It exits non-zero in a bare sandbox
  # (missing tools) — fine; it must NOT die on a bash-4 associative array.
  run /bin/bash "$REPO/bin/dot-doctor"
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" == *"Homebrew Packages"* ]]
}

@test "check_sdk recognizes a candidate installed via SDKMAN but not on PATH" {
  mkdir -p "$SANDBOX/.sdkman/candidates/kotlin/current/bin"
  printf '#!/bin/sh\n' >"$SANDBOX/.sdkman/candidates/kotlin/current/bin/kotlin"
  chmod +x "$SANDBOX/.sdkman/candidates/kotlin/current/bin/kotlin"
  # Source doctor (main is guarded), then check with a PATH that lacks kotlin.
  run env TERM=dumb bash -c "
    source '$REPO/bin/dot-doctor'
    SDKMAN_DIR='$SANDBOX/.sdkman' PATH='/usr/bin:/bin' check_sdk kotlin kotlin true
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"installed"* ]]
  [[ "$output" != *"not found"* ]]
}

@test "doctor --help documents --strict and exits 0" {
  run env DOTFILES="$REPO" TERM=dumb "$REPO/bin/dot-doctor" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--strict"* ]]
}

@test "doctor rejects an unknown option" {
  run env DOTFILES="$REPO" TERM=dumb "$REPO/bin/dot-doctor" --nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
}
