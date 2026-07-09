setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export REPO TERM=dumb
  SANDBOX="$(mktemp -d)"
  export SANDBOX
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Fixture mirrors the prune/adopt suites: declared git (core) + terraform-docs
# (work, "declared elsewhere"); undeclared htop/wget (formulas) + somecask
# (cask); toolchain declares gradle, scala installed ad-hoc; plugin a/b
# declared, c/orphan an undeclared clone.
setup_ignore_fixture() {
  mkdir -p "$SANDBOX/bin" "$SANDBOX/home/.config" "$SANDBOX/dotfiles/brew" \
    "$SANDBOX/dotfiles/sdkman" "$SANDBOX/dotfiles/home" "$SANDBOX/dotfiles/config" \
    "$SANDBOX/.sdkman/bin"
  printf "brew 'git'\n" >"$SANDBOX/dotfiles/brew/Brewfile.core"
  printf "brew 'terraform-docs'\n" >"$SANDBOX/dotfiles/brew/Brewfile.work"
  printf 'gradle\n' >"$SANDBOX/dotfiles/sdkman/toolchain"
  printf 'zfetch a/b\n' >"$SANDBOX/dotfiles/home/.zshrc"
  mkdir -p "$SANDBOX/plugins/a/b/.git" "$SANDBOX/plugins/c/orphan/.git"
  mkdir -p "$SANDBOX/.sdkman/candidates/gradle/8.5" \
    "$SANDBOX/.sdkman/candidates/scala/3.4"
  cat >"$SANDBOX/bin/brew" <<'EOF'
#!/bin/bash
case "$1 ${2:-}" in
  "leaves ") printf '%s\n' git htop wget terraform-docs ;;
  "list --formula") printf '%s\n' git htop wget terraform-docs ;;
  "list --cask") printf '%s\n' somecask ;;
esac
EOF
  chmod +x "$SANDBOX/bin/brew"
}

run_driver() {
  run env PATH="$SANDBOX/bin:/usr/bin:/bin" HOME="$SANDBOX/home" \
    XDG_CONFIG_HOME="$SANDBOX/home/.config" DOTFILES="$SANDBOX/dotfiles" \
    HOMEBREW_CACHE="$SANDBOX/brew-cache" ZPLUGDIR="$SANDBOX/plugins" \
    SDKMAN_DIR="$SANDBOX/.sdkman" \
    TERM=dumb bash "$REPO/bin/dot-reconcile" "$@"
}

IGNORE_FILE_REL="home/.config/dotfiles/reconcile-ignore"

@test "ignore: an undeclared brew is recorded in the machine-local ignore file, not a Brewfile" {
  setup_ignore_fixture
  run_driver brew --ignore htop
  [ "$status" -eq 0 ]
  grep -qx "brew htop" "$SANDBOX/$IGNORE_FILE_REL"
  ! grep -q "htop" "$SANDBOX/dotfiles/brew/Brewfile.core"
  ! grep -q "htop" "$SANDBOX/dotfiles/brew/Brewfile.personal" 2>/dev/null
}

@test "ignore: an ignored item is excluded from reconcile_brew_undeclared" {
  setup_ignore_fixture
  run_driver brew --ignore htop
  [ "$status" -eq 0 ]
  run env PATH="$SANDBOX/bin:/usr/bin:/bin" HOME="$SANDBOX/home" \
    XDG_CONFIG_HOME="$SANDBOX/home/.config" DOTFILES="$SANDBOX/dotfiles" \
    HOMEBREW_CACHE="$SANDBOX/brew-cache" bash -c \
    "source '$REPO/bin/lib/reconcile.sh'; reconcile_brew_undeclared"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wget"* ]] # still undeclared
  [[ "$output" != *"htop"* ]] # excluded once ignored
}

@test "ignore: an ignored, still-installed item shows in the dim 'ignored (informational)' section" {
  setup_ignore_fixture
  run_driver brew --ignore htop
  [ "$status" -eq 0 ]
  run_driver brew
  [[ "$output" == *"ignored (informational)"* ]]
  [[ "$output" == *"htop"* ]]
}

@test "ignore: declared and declared-elsewhere names are refused" {
  setup_ignore_fixture
  run_driver brew --ignore git
  [ "$status" -ne 0 ]
  run_driver brew --ignore terraform-docs
  [ "$status" -ne 0 ]
  [ ! -s "$SANDBOX/$IGNORE_FILE_REL" ]
}

@test "ignore: --all ignores every undeclared brew item" {
  setup_ignore_fixture
  run_driver brew --ignore --all
  [ "$status" -eq 0 ]
  grep -qx "brew htop" "$SANDBOX/$IGNORE_FILE_REL"
  grep -qx "brew wget" "$SANDBOX/$IGNORE_FILE_REL"
  grep -qx "brew somecask" "$SANDBOX/$IGNORE_FILE_REL"
  run_driver brew
  [[ "$output" != *"undeclared (installed"* ]] # nothing left undeclared — header itself is suppressed
  [[ "$output" == *"ignored (informational)"* ]]
}

@test "ignore: --all on a fully-declared domain ignores nothing and succeeds" {
  setup_ignore_fixture
  cat >"$SANDBOX/bin/brew" <<'EOF'
#!/bin/bash
case "$1 ${2:-}" in
  "leaves ") printf '%s\n' git terraform-docs ;;
  "list --formula") printf '%s\n' git terraform-docs ;;
  "list --cask") : ;;
esac
EOF
  run_driver brew --ignore --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing undeclared"* ]]
  [ ! -f "$SANDBOX/$IGNORE_FILE_REL" ]
}

@test "unignore: reverses ignore — the item reappears as undeclared" {
  setup_ignore_fixture
  run_driver brew --ignore htop
  [ "$status" -eq 0 ]
  run_driver brew --unignore htop
  [ "$status" -eq 0 ]
  ! grep -qx "brew htop" "$SANDBOX/$IGNORE_FILE_REL"
  run_driver brew
  [[ "$output" == *"htop"* ]]
}

@test "unignore: a name that is not currently ignored is refused" {
  setup_ignore_fixture
  run_driver brew --unignore htop
  [ "$status" -ne 0 ]
  [[ "$output" == *"not currently ignored"* ]]
}

@test "ignore/unignore round-trips for sdkman and plugins domains too" {
  setup_ignore_fixture
  run_driver sdkman --ignore scala
  [ "$status" -eq 0 ]
  grep -qx "sdkman scala" "$SANDBOX/$IGNORE_FILE_REL"
  run_driver sdkman
  [[ "$output" == *"ignored (informational)"* ]]

  run_driver plugins --ignore c/orphan
  [ "$status" -eq 0 ]
  grep -qx "plugins c/orphan" "$SANDBOX/$IGNORE_FILE_REL"

  run_driver sdkman --unignore scala
  [ "$status" -eq 0 ]
  ! grep -qx "sdkman scala" "$SANDBOX/$IGNORE_FILE_REL"
}

@test "ignore: symlinks domain has no ignore concept" {
  setup_ignore_fixture
  run_driver symlinks --ignore --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"no ignore/unignore concept"* ]]
}

@test "ignore: --ignore and --adopt are mutually exclusive" {
  setup_ignore_fixture
  run_driver brew --ignore --adopt htop
  [ "$status" -ne 0 ]
}

@test "ignore: ignoring the same item twice does not duplicate the ignore-file line" {
  setup_ignore_fixture
  run env HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/home/.config" \
    DOTFILES="$SANDBOX/dotfiles" bash -c \
    "source '$REPO/bin/lib/reconcile.sh'; reconcile_brew_ignore htop; reconcile_brew_ignore htop"
  [ "$status" -eq 0 ]
  [ "$(grep -cx "brew htop" "$SANDBOX/$IGNORE_FILE_REL")" -eq 1 ]
}
