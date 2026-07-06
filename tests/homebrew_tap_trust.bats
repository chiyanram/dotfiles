#!/usr/bin/env bats
# dot-homebrew bundle — Homebrew 6 tap-trust handling (#17).
# Untrusted third-party taps hard-fail `brew bundle` even for a core-only
# Brewfile. Policy: auto-trust only taps with packages installed from them
# (revealed dependence); warn about the rest; never fail the step.

load test_helper

setup() {
  setup_sandbox
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  BREW_LOG="$SANDBOX/brew.log"
  FAKE_CELLAR="$SANDBOX/cellar"
  FAKE_CASKROOM="$SANDBOX/caskroom"
  export BREW_LOG FAKE_CELLAR FAKE_CASKROOM

  mkdir -p "$SANDBOX/bin" "$FAKE_CELLAR" "$FAKE_CASKROOM" "$DOTFILES/brew"
  : >"$BREW_LOG"
  printf "brew 'git'\n" >"$DOTFILES/brew/Brewfile.core"

  # Fake brew: parametrized via FAKE_BREW_* env vars, records every call.
  cat >"$SANDBOX/bin/brew" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${BREW_LOG:?}"
case "$1" in
  trust)
    if [ "${2:-}" = "--json=v1" ]; then
      if [ "${FAKE_BREW_HAS_TRUST:-1}" = "1" ]; then
        printf '{"taps": []}\n'
        exit 0
      fi
      printf 'Error: Unknown command: trust\n' >&2
      exit 1
    fi
    exit 0 # brew trust --tap <name>
    ;;
  tap)
    for t in ${FAKE_BREW_TAPS:-}; do printf '%s\n' "$t"; done
    ;;
  tap-info)
    printf '%s: Installed\n' "$2"
    case " ${FAKE_BREW_UNTRUSTED:-} " in
      *" $2 "*) printf 'Untrusted\n' ;;
      *) printf 'Trusted\n' ;;
    esac
    ;;
  --cellar) printf '%s\n' "${FAKE_CELLAR:?}" ;;
  --caskroom) printf '%s\n' "${FAKE_CASKROOM:?}" ;;
  --prefix) printf '%s\n' "$HOME/nonexistent-prefix" ;;
  bundle) exit 0 ;;
esac
exit 0
EOF
  chmod +x "$SANDBOX/bin/brew"
}

teardown() { teardown_sandbox; }

# Write an INSTALL_RECEIPT.json recording $2 as the source tap of formula $1.
install_formula_receipt() {
  mkdir -p "$FAKE_CELLAR/$1/1.0.0"
  printf '{"source":{"tap":"%s"}}\n' "$2" >"$FAKE_CELLAR/$1/1.0.0/INSTALL_RECEIPT.json"
}

# Same, for a cask in the Caskroom (pretty-printed like real cask receipts).
install_cask_receipt() {
  mkdir -p "$FAKE_CASKROOM/$1/.metadata"
  printf '{"source": {"tap": "%s"}}\n' "$2" >"$FAKE_CASKROOM/$1/.metadata/INSTALL_RECEIPT.json"
}

run_bundle() {
  run env PATH="$SANDBOX/bin:/usr/bin:/bin" HOME="$HOME" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    DOTFILES="$DOTFILES" TERM=dumb \
    BREW_LOG="$BREW_LOG" FAKE_CELLAR="$FAKE_CELLAR" FAKE_CASKROOM="$FAKE_CASKROOM" \
    FAKE_BREW_HAS_TRUST="${FAKE_BREW_HAS_TRUST:-1}" \
    FAKE_BREW_TAPS="${FAKE_BREW_TAPS:-}" \
    FAKE_BREW_UNTRUSTED="${FAKE_BREW_UNTRUSTED:-}" \
    bash "$REPO/bin/dot-homebrew" bundle
}

@test "bundle trusts untrusted taps that have packages installed from them" {
  export FAKE_BREW_TAPS="hashicorp/tap onepassword/tap"
  export FAKE_BREW_UNTRUSTED="hashicorp/tap onepassword/tap"
  install_formula_receipt terraform hashicorp/tap
  install_cask_receipt 1password-cli onepassword/tap

  run_bundle
  [ "$status" -eq 0 ]
  grep -qx "trust --tap hashicorp/tap" "$BREW_LOG"
  grep -qx "trust --tap onepassword/tap" "$BREW_LOG"
  grep -q "^bundle --file=" "$BREW_LOG" # bundling still happened
}

@test "bundle warns and skips untrusted taps with nothing installed" {
  export FAKE_BREW_TAPS="kaos/shell"
  export FAKE_BREW_UNTRUSTED="kaos/shell"

  run_bundle
  [ "$status" -eq 0 ]
  [[ "$output" == *"kaos/shell"* ]]
  [[ "$output" == *"brew trust --tap kaos/shell"* ]]
  [[ "$output" == *"brew untap kaos/shell"* ]]
  ! grep -q "^trust --tap" "$BREW_LOG"
  grep -q "^bundle --file=" "$BREW_LOG"
}

@test "bundle leaves already-trusted and official taps alone" {
  export FAKE_BREW_TAPS="homebrew/services nikitabobko/tap"
  export FAKE_BREW_UNTRUSTED="" # nikitabobko/tap is already trusted

  run_bundle
  [ "$status" -eq 0 ]
  ! grep -q "^trust --tap" "$BREW_LOG"
  ! grep -q "^tap-info homebrew/services" "$BREW_LOG" # official: implicitly trusted
  [[ "$output" != *"Untrusted"* ]]
}

@test "bundle tap-trust is a no-op when no taps exist (day-0)" {
  export FAKE_BREW_TAPS=""

  run_bundle
  [ "$status" -eq 0 ]
  ! grep -q "^trust --tap" "$BREW_LOG"
  ! grep -q "^tap-info" "$BREW_LOG"
  [[ "$output" != *"Untrusted"* ]]
}

@test "bundle skips tap-trust when brew has no trust command (pre-6)" {
  export FAKE_BREW_HAS_TRUST=0
  export FAKE_BREW_TAPS="hashicorp/tap"
  export FAKE_BREW_UNTRUSTED="hashicorp/tap"

  run_bundle
  [ "$status" -eq 0 ]
  ! grep -q "^trust --tap" "$BREW_LOG"
  ! grep -q "^tap-info" "$BREW_LOG"
  grep -q "^bundle --file=" "$BREW_LOG"
}
