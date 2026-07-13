setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export REPO TERM=dumb
  SANDBOX="$(mktemp -d)"
  export SANDBOX
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Fixture: declared git (core) + terraform-docs (work profile, "declared
# elsewhere" on the personal machine); installed htop + wget (undeclared
# formulas) and somecask (undeclared cask). The fake brew logs every mutating
# call so tests assert exactly what would be uninstalled.
setup_prune_fixture() {
  mkdir -p "$SANDBOX/bin" "$SANDBOX/home/.config" "$SANDBOX/dotfiles/brew" \
    "$SANDBOX/dotfiles/sdkman" "$SANDBOX/dotfiles/home" "$SANDBOX/dotfiles/config" \
    "$SANDBOX/.sdkman/bin"
  printf "brew 'git'\n" >"$SANDBOX/dotfiles/brew/Brewfile.core"
  printf "brew 'terraform-docs'\n" >"$SANDBOX/dotfiles/brew/Brewfile.work"
  printf 'gradle\n' >"$SANDBOX/dotfiles/sdkman/toolchain"
  printf 'zfetch a/b\n' >"$SANDBOX/dotfiles/home/.zshrc"
  mkdir -p "$SANDBOX/plugins/a/b/.git" "$SANDBOX/plugins/c/orphan/.git" \
    "$SANDBOX/plugins/c/orphan2/.git"
  mkdir -p "$SANDBOX/.sdkman/candidates/gradle/8.5" \
    "$SANDBOX/.sdkman/candidates/scala/3.3" "$SANDBOX/.sdkman/candidates/scala/3.4"
  ln -s "$SANDBOX/.sdkman/candidates/scala/3.4" "$SANDBOX/.sdkman/candidates/scala/current"
  cat >"$SANDBOX/bin/brew" <<'EOF'
#!/bin/bash
case "$1 ${2:-}" in
  "leaves ") printf '%s\n' git htop wget terraform-docs ;;
  "list --formula") printf '%s\n' git htop wget terraform-docs ;;
  "list --cask") printf '%s\n' somecask ;;
  uninstall*) echo "$*" >>"${BREW_LOG:?}" ;; # only mutations are logged
esac
EOF
  chmod +x "$SANDBOX/bin/brew"
  # run_sdk sources this in a subprocess; the fake sdk only logs.
  cat >"$SANDBOX/.sdkman/bin/sdkman-init.sh" <<'EOF'
sdk() { echo "sdk $*" >>"${SDK_LOG:?}"; }
EOF
  export BREW_LOG="$SANDBOX/brew.log" SDK_LOG="$SANDBOX/sdk.log"
  : >"$BREW_LOG"
  : >"$SDK_LOG"
}

run_driver() {
  run env PATH="$SANDBOX/bin:/usr/bin:/bin" HOME="$SANDBOX/home" \
    XDG_CONFIG_HOME="$SANDBOX/home/.config" DOTFILES="$SANDBOX/dotfiles" \
    DOT_TEST_DOTFILES="$SANDBOX/dotfiles" \
    HOMEBREW_CACHE="$SANDBOX/brew-cache" ZPLUGDIR="$SANDBOX/plugins" \
    SDKMAN_DIR="$SANDBOX/.sdkman" BREW_LOG="$BREW_LOG" SDK_LOG="$SDK_LOG" \
    TERM=dumb bash "$REPO/bin/dot-reconcile" "$@"
}

@test "prune: a named undeclared plugin clone is removed, others untouched" {
  setup_prune_fixture
  run_driver plugins --prune c/orphan
  [ "$status" -eq 0 ]
  [ ! -d "$SANDBOX/plugins/c/orphan" ]  # named orphan gone
  [ -d "$SANDBOX/plugins/c/orphan2" ]   # other orphan untouched
  [ -d "$SANDBOX/plugins/a/b" ]         # declared clone untouched
}

@test "prune: no names and no --all destroys nothing and fails" {
  setup_prune_fixture
  run_driver plugins --prune
  [ "$status" -ne 0 ]
  [ -d "$SANDBOX/plugins/c/orphan" ]
  [ -d "$SANDBOX/plugins/c/orphan2" ]
}

@test "prune: --all removes all undeclared brews, never declared or declared-elsewhere" {
  setup_prune_fixture
  run_driver brew --prune --all
  [ "$status" -eq 0 ]
  run cat "$BREW_LOG"
  [[ "$output" == *"uninstall htop"* ]]
  [[ "$output" == *"uninstall wget"* ]]
  [[ "$output" == *"uninstall --cask somecask"* ]]
  [[ "$output" != *"git"* ]]            # declared (core)
  [[ "$output" != *"terraform-docs"* ]] # declared elsewhere (work profile)
}

@test "prune: a declared package is refused" {
  setup_prune_fixture
  run_driver brew --prune git
  [ "$status" -ne 0 ]
  [[ "$output" == *"git"* && "$output" == *"refus"* ]]
  [ ! -s "$BREW_LOG" ] # nothing uninstalled
}

@test "prune: a declared-elsewhere package is refused" {
  setup_prune_fixture
  run_driver brew --prune terraform-docs
  [ "$status" -ne 0 ]
  [ ! -s "$BREW_LOG" ]
}

@test "prune: a package declared under an alias is never prunable (canonical name refused)" {
  setup_prune_fixture
  # kubectl declared; brew installs/lists the canonical kubernetes-cli
  printf "brew 'git'\nbrew 'kubectl'\n" >"$SANDBOX/dotfiles/brew/Brewfile.core"
  mkdir -p "$SANDBOX/brew-cache/api"
  printf 'kubectl|kubernetes-cli\n' >"$SANDBOX/brew-cache/api/formula_aliases.txt"
  cat >"$SANDBOX/bin/brew" <<'EOF'
#!/bin/bash
case "$1 ${2:-}" in
  "leaves ") printf '%s\n' git kubernetes-cli htop ;;
  "list --formula") printf '%s\n' git kubernetes-cli htop ;;
  "list --cask") : ;;
  uninstall*) echo "$*" >>"${BREW_LOG:?}" ;;
esac
EOF
  run_driver brew --prune kubernetes-cli
  [ "$status" -ne 0 ]
  [ ! -s "$BREW_LOG" ]
  # ...and --all's prune set excludes it too
  run_driver brew --prune --all
  [ "$status" -eq 0 ]
  run cat "$BREW_LOG"
  [[ "$output" == *"uninstall htop"* ]]
  [[ "$output" != *"kubernetes-cli"* ]]
}

@test "prune: an undeclared sdkman candidate is uninstalled version by version" {
  setup_prune_fixture
  run_driver sdkman --prune scala
  [ "$status" -eq 0 ]
  run cat "$SDK_LOG"
  [[ "$output" == *"sdk uninstall scala 3.3"* ]]
  [[ "$output" == *"sdk uninstall scala 3.4"* ]]
  [[ "$output" != *"current"* ]] # the `current` symlink is not a version
  [[ "$output" != *"gradle"* ]]  # declared candidate untouched
}

@test "prune: symlinks domain has no prune — points at dot clean" {
  setup_prune_fixture
  run_driver symlinks --prune --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"dot clean"* ]]
}

@test "prune: --prune without a domain fails" {
  setup_prune_fixture
  run_driver --prune --all
  [ "$status" -ne 0 ]
  [ ! -s "$BREW_LOG" ]
  [ -d "$SANDBOX/plugins/c/orphan" ]
}

@test "prune: --all on a converged domain prunes nothing and succeeds" {
  setup_prune_fixture
  rm -rf "$SANDBOX/plugins/c" # remove both orphans → plugins converged
  run_driver plugins --prune --all
  [ "$status" -eq 0 ]
  [ -d "$SANDBOX/plugins/a/b" ]
}
