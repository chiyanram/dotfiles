setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  # Run doctor with a minimal PATH so slow dev-tool probes (gradle/java `--version`,
  # brew, sdk) resolve to "not found" instantly instead of shelling out — ~24s → ~2s
  # per run, and deterministic (fresh-machine-like) rather than machine-dependent.
  DOCTOR_PATH="/usr/bin:/bin"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "doctor shows the active profile and resolved docker runtime" {
  [[ "$(uname)" == "Darwin" ]] || skip "dot doctor inspection is macOS-only"
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$REPO" TERM=dumb
  "$REPO/bin/dot-profile" set work
  # doctor exits non-zero in a sandbox (missing links/tools) — ignore that; check output.
  run env PATH="$DOCTOR_PATH" "$REPO/bin/dot-doctor"
  [[ "$output" == *"Profile"* ]]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"rancher"* ]]
}

@test "doctor defaults to the personal profile and docker-desktop runtime" {
  [[ "$(uname)" == "Darwin" ]] || skip "dot doctor inspection is macOS-only"
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$REPO" TERM=dumb
  run env PATH="$DOCTOR_PATH" "$REPO/bin/dot-doctor"
  [[ "$output" == *"personal"* ]]
  [[ "$output" == *"docker-desktop"* ]]
}

@test "doctor runs under system bash 3.2 without the associative-array crash" {
  [[ "$(uname)" == "Darwin" ]] || skip "system bash 3.2 is macOS-only"
  [[ -x /bin/bash ]] || skip "no /bin/bash"
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$REPO" TERM=dumb
  # A fresh Mac runs doctor under bash 3.2. It exits non-zero in a bare sandbox
  # (missing tools) — fine; it must NOT die on a bash-4 associative array.
  run env PATH="$DOCTOR_PATH" /bin/bash "$REPO/bin/dot-doctor"
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

@test "doctor surfaces a drift summary pointing at dot reconcile" {
  [[ "$(uname)" == "Darwin" ]] || skip "dot doctor inspection is macOS-only"
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$REPO" TERM=dumb
  # Sandbox HOME has none of the repo's declared state → drift is guaranteed
  # (declared plugins not cloned, toolchain not installed). Doctor must show the
  # per-domain summary and point at dot reconcile — informational, not gating.
  run env PATH="$DOCTOR_PATH" "$REPO/bin/dot-doctor"
  [[ "$output" == *"Drift"* ]]
  [[ "$output" == *"missing"* ]]
  [[ "$output" == *"dot reconcile"* ]]
}

@test "doctor names a deleted-source home dangle in the stale section (#46)" {
  [[ "$(uname)" == "Darwin" ]] || skip "dot doctor inspection is macOS-only"
  # Fixture DOTFILES git repo where home/.claude/settings.json was linked, then
  # deleted from the repo — only git history can name the dangle (#21 shape).
  mkdir -p "$SANDBOX/dotfiles/bin/lib" "$SANDBOX/dotfiles/home/.claude" "$SANDBOX/.claude" "$SANDBOX/.config"
  cp "$REPO/bin/lib/common.sh" "$REPO/bin/lib/reconcile.sh" "$SANDBOX/dotfiles/bin/lib/"
  touch "$SANDBOX/dotfiles/home/.zshrc"
  printf '{}\n' >"$SANDBOX/dotfiles/home/.claude/settings.json"
  git -C "$SANDBOX/dotfiles" init -q
  git -C "$SANDBOX/dotfiles" -c user.email=t@t -c user.name=t add -A
  git -C "$SANDBOX/dotfiles" -c user.email=t@t -c user.name=t commit -qm init
  ln -s "$SANDBOX/dotfiles/home/.claude/settings.json" "$SANDBOX/.claude/settings.json"
  git -C "$SANDBOX/dotfiles" rm -q home/.claude/settings.json
  git -C "$SANDBOX/dotfiles" -c user.email=t@t -c user.name=t commit -qm "remove claude"
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$SANDBOX/dotfiles" TERM=dumb
  run env PATH="$DOCTOR_PATH" "$REPO/bin/dot-doctor"
  [[ "$output" == *"stale"* ]]
  [[ "$output" == *".claude/settings.json"* ]]
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

@test "doctor's Homebrew checklist respects Brewfile OS conditionals (#42)" {
  [[ "$(uname)" == "Darwin" ]] || skip "dot doctor inspection is macOS-only"
  # Fixture DOTFILES: doctor must derive its checklist from the reconcile
  # declared pipeline, so a linux-only formula never shows up on macOS.
  mkdir -p "$SANDBOX/dotfiles/bin/lib" "$SANDBOX/dotfiles/brew" "$SANDBOX/dotfiles/home" "$SANDBOX/.config"
  cp "$REPO/bin/lib/common.sh" "$REPO/bin/lib/reconcile.sh" "$SANDBOX/dotfiles/bin/lib/"
  touch "$SANDBOX/dotfiles/home/.zshrc"
  cat >"$SANDBOX/dotfiles/brew/Brewfile.core" <<'BREWFILE'
brew 'jq' # everywhere
if OS.mac?
  cask 'ghostty' # mac app
elsif OS.linux?
  brew 'xclip' # linux-only clipboard
end
BREWFILE
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$SANDBOX/dotfiles" TERM=dumb
  run env PATH="$DOCTOR_PATH" "$REPO/bin/dot-doctor"
  [[ "$output" == *"jq"* ]]    # active-OS formula still checked
  [[ "$output" != *"xclip"* ]] # linux-only formula must not appear (#37/#39 parity)
}
