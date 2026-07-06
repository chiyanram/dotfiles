setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export REPO TERM=dumb
  SANDBOX="$(mktemp -d)"
  export SANDBOX
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Fixture mirrors the prune suite: declared git (core) + terraform-docs (work,
# "declared elsewhere"); undeclared htop/wget (formulas) + somecask (cask);
# toolchain declares gradle; scala + java installed ad-hoc; plugin a/b declared,
# c/orphan an undeclared clone. The fake zsh is the smoke-test seam: it fails
# iff $ZSH_FAIL exists, so tests can force the plugins revert path.
setup_adopt_fixture() {
  mkdir -p "$SANDBOX/bin" "$SANDBOX/home/.config" "$SANDBOX/dotfiles/brew" \
    "$SANDBOX/dotfiles/sdkman" "$SANDBOX/dotfiles/home" "$SANDBOX/dotfiles/config" \
    "$SANDBOX/.sdkman/bin"
  printf "brew 'git'\n" >"$SANDBOX/dotfiles/brew/Brewfile.core"
  : >"$SANDBOX/dotfiles/brew/Brewfile.personal"
  printf "brew 'terraform-docs'\n" >"$SANDBOX/dotfiles/brew/Brewfile.work"
  printf 'gradle\n' >"$SANDBOX/dotfiles/sdkman/toolchain"
  cat >"$SANDBOX/dotfiles/home/.zshrc" <<'EOF'
# plugins
zfetch a/b
zfetch x/y extra.zsh
# post-plugin section
bindkey something
EOF
  mkdir -p "$SANDBOX/plugins/a/b/.git" "$SANDBOX/plugins/x/y/.git" \
    "$SANDBOX/plugins/c/orphan/.git"
  mkdir -p "$SANDBOX/.sdkman/candidates/gradle/8.5" \
    "$SANDBOX/.sdkman/candidates/scala/3.4" \
    "$SANDBOX/.sdkman/candidates/java/21.0.1-tem" \
    "$SANDBOX/.sdkman/candidates/java/17.0.9-tem" \
    "$SANDBOX/.sdkman/candidates/java/21.0.4-graalce"
  ln -s "$SANDBOX/.sdkman/candidates/java/21.0.1-tem" \
    "$SANDBOX/.sdkman/candidates/java/current"
  cat >"$SANDBOX/bin/brew" <<'EOF'
#!/bin/bash
case "$1 ${2:-}" in
  "leaves ") printf '%s\n' git htop wget terraform-docs ;;
  "list --formula") printf '%s\n' git htop wget terraform-docs ;;
  "list --cask") printf '%s\n' somecask ;;
esac
EOF
  cat >"$SANDBOX/bin/zsh" <<'EOF'
#!/bin/bash
[ -e "${ZSH_FAIL:-/nonexistent}" ] && exit 1
echo ok
EOF
  chmod +x "$SANDBOX/bin/brew" "$SANDBOX/bin/zsh"
  export ZSH_FAIL="$SANDBOX/zsh-fail" # not created — smoke passes by default
}

run_driver() {
  run env PATH="$SANDBOX/bin:/usr/bin:/bin" HOME="$SANDBOX/home" \
    XDG_CONFIG_HOME="$SANDBOX/home/.config" DOTFILES="$SANDBOX/dotfiles" \
    HOMEBREW_CACHE="$SANDBOX/brew-cache" ZPLUGDIR="$SANDBOX/plugins" \
    SDKMAN_DIR="$SANDBOX/.sdkman" ZSH_FAIL="$ZSH_FAIL" \
    TERM=dumb bash "$REPO/bin/dot-reconcile" "$@"
}

@test "adopt: an undeclared brew lands in the active-profile Brewfile, uncommitted" {
  setup_adopt_fixture
  git -C "$SANDBOX/dotfiles" init -q
  git -C "$SANDBOX/dotfiles" -c user.email=t@t -c user.name=t add -A
  git -C "$SANDBOX/dotfiles" -c user.email=t@t -c user.name=t commit -qm init
  run_driver brew --adopt htop
  [ "$status" -eq 0 ]
  grep -q "^brew 'htop'" "$SANDBOX/dotfiles/brew/Brewfile.personal"
  ! grep -q "htop" "$SANDBOX/dotfiles/brew/Brewfile.core"
  # edited, but never committed — the diff is the user's to review
  run git -C "$SANDBOX/dotfiles" status --porcelain
  [[ "$output" == *"Brewfile.personal"* ]]
  [ "$(git -C "$SANDBOX/dotfiles" rev-list --count HEAD)" -eq 1 ]
}

@test "adopt: --to core promotes the entry to Brewfile.core" {
  setup_adopt_fixture
  run_driver brew --adopt htop --to core
  [ "$status" -eq 0 ]
  grep -q "^brew 'htop'" "$SANDBOX/dotfiles/brew/Brewfile.core"
  ! grep -q "htop" "$SANDBOX/dotfiles/brew/Brewfile.personal"
}

@test "adopt: an installed cask is adopted as a cask entry" {
  setup_adopt_fixture
  run_driver brew --adopt somecask
  [ "$status" -eq 0 ]
  grep -q "^cask 'somecask'" "$SANDBOX/dotfiles/brew/Brewfile.personal"
}

@test "adopt: declared-elsewhere is refused (it is already declared)" {
  setup_adopt_fixture
  run_driver brew --adopt terraform-docs
  [ "$status" -ne 0 ]
  ! grep -q "terraform-docs" "$SANDBOX/dotfiles/brew/Brewfile.personal"
  ! grep -q "terraform-docs" "$SANDBOX/dotfiles/brew/Brewfile.core"
}

@test "adopt: --all adopts every undeclared brew item" {
  setup_adopt_fixture
  run_driver brew --adopt --all
  [ "$status" -eq 0 ]
  grep -q "^brew 'htop'" "$SANDBOX/dotfiles/brew/Brewfile.personal"
  grep -q "^brew 'wget'" "$SANDBOX/dotfiles/brew/Brewfile.personal"
  grep -q "^cask 'somecask'" "$SANDBOX/dotfiles/brew/Brewfile.personal"
}

@test "adopt: an sdkman tool is appended to the toolchain as a bare candidate" {
  setup_adopt_fixture
  run_driver sdkman --adopt scala
  [ "$status" -eq 0 ]
  grep -qx "scala" "$SANDBOX/dotfiles/sdkman/toolchain"
}

@test "adopt: java adopts Temurin majors; a non-Temurin JDK is manual" {
  setup_adopt_fixture
  run_driver sdkman --adopt java
  [ "$status" -eq 0 ]
  grep -qx "java 17" "$SANDBOX/dotfiles/sdkman/toolchain"
  grep -qx "java 21" "$SANDBOX/dotfiles/sdkman/toolchain"
  ! grep -q "graalce" "$SANDBOX/dotfiles/sdkman/toolchain"
  [[ "$output" == *"21.0.4-graalce"* && "$output" == *"hand"* ]] # adopt by hand
}

@test "adopt: a plugin is inserted after the last zfetch line and the shell smoke passes" {
  setup_adopt_fixture
  run_driver plugins --adopt c/orphan
  [ "$status" -eq 0 ]
  # inserted inside the plugin group: after `zfetch x/y`, before the post section
  run awk '/zfetch x\/y/{found=1;next} found{print;exit}' "$SANDBOX/dotfiles/home/.zshrc"
  [[ "$output" == *"zfetch c/orphan"* ]]
}

@test "adopt: a failing shell smoke reverts the .zshrc edit" {
  setup_adopt_fixture
  touch "$ZSH_FAIL" # fake zsh now exits 1
  cp "$SANDBOX/dotfiles/home/.zshrc" "$SANDBOX/zshrc.before"
  run_driver plugins --adopt c/orphan
  [ "$status" -ne 0 ]
  [[ "$output" == *"revert"* ]]
  diff -q "$SANDBOX/zshrc.before" "$SANDBOX/dotfiles/home/.zshrc"
}

@test "adopt: --to core is only for the brew domain" {
  setup_adopt_fixture
  run_driver sdkman --adopt scala --to core
  [ "$status" -ne 0 ]
  ! grep -qx "scala" "$SANDBOX/dotfiles/sdkman/toolchain"
}

@test "adopt: no names and no --all edits nothing and fails" {
  setup_adopt_fixture
  run_driver brew --adopt
  [ "$status" -ne 0 ]
  [ ! -s "$SANDBOX/dotfiles/brew/Brewfile.personal" ]
}

@test "adopt: --prune and --adopt are mutually exclusive" {
  setup_adopt_fixture
  run_driver brew --prune --adopt htop
  [ "$status" -ne 0 ]
  [ ! -s "$SANDBOX/dotfiles/brew/Brewfile.personal" ]
}
