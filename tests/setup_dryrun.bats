setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "setup --dry-run lists steps and writes nothing" {
  run env HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$REPO" TERM=dumb \
    "$REPO/setup.sh" --dry-run --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"would run: Xcode Command Line Tools"* ]]
  [[ "$output" == *"would run: Machine profile"* ]]
  [[ "$output" == *"would run: Homebrew packages"* ]]
  [[ "$output" == *"would run: Health check"* ]]
  # Dry-run must have NO side effects:
  [ ! -f "$SANDBOX/.config/dotfiles/profile" ]
  [ ! -f "$SANDBOX/.ssh/id_ed25519" ]
}

@test "setup --help exits 0" {
  run env DOTFILES="$REPO" TERM=dumb "$REPO/setup.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--profile"* ]]
}

@test "setup rejects an invalid --profile" {
  run env HOME="$SANDBOX" DOTFILES="$REPO" TERM=dumb "$REPO/setup.sh" --profile staging --dry-run
  [ "$status" -ne 0 ]
}

@test "setup --profile with no argument exits non-zero" {
  run env HOME="$SANDBOX" DOTFILES="$REPO" TERM=dumb "$REPO/setup.sh" --profile
  [ "$status" -ne 0 ]
}

@test "step_sdkman skips with guidance when PATH bash is < 4 (probes PATH bash, not \$BASH_VERSINFO)" {
  # Fake bash on PATH reporting major version 3, only for the version probe;
  # everything else delegates to the real bash.
  mkdir -p "$SANDBOX/fakebin"
  cat >"$SANDBOX/fakebin/bash" <<'EOF'
#!/bin/sh
case "$*" in
  *BASH_VERSINFO*) echo 3 ;;
  *) exec /bin/bash "$@" ;;
esac
EOF
  chmod +x "$SANDBOX/fakebin/bash"
  # Run the harness under the REAL (modern) bash by absolute path, so $BASH_VERSINFO
  # is >= 4. If the guard skips anyway, it proves it read the PATH bash (3), not the
  # running shell's version.
  local realbash
  realbash="$(command -v bash)"
  run env DOTFILES="$REPO" HOME="$SANDBOX" TERM=dumb PATH="$SANDBOX/fakebin:$PATH" \
    "$realbash" -c '
      source "$DOTFILES/setup.sh"
      ask_yes_no() { return 0; }           # pretend the user said "yes, install"
      configure_sdkman_auto_env() { :; }   # stub (not under test)
      rc=0; step_sdkman || rc=$?
      echo "step_rc=$rc"
    '
  [[ "$output" == *"needs bash >= 4"* ]]
  [[ "$output" == *"step_rc=78"* ]]   # STEP_SKIP_CODE — skipped, did not curl|bash
}
