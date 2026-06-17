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
