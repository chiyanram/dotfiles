setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export REPO TERM=dumb
  SANDBOX="$(mktemp -d)"
  export SANDBOX
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Source the reconcile lib from the real repo, but point DOTFILES/ZPLUGDIR at the
# sandbox so declared (repo .zshrc) and actual (cloned plugin dirs) are fixtures.
plugins_undeclared() {
  run env DOTFILES="$SANDBOX/dotfiles" ZPLUGDIR="$SANDBOX/plugins" REPO="$REPO" bash -c '
    source "$REPO/bin/lib/reconcile.sh"
    reconcile_plugins_undeclared
  '
}

@test "plugins: an installed clone the .zshrc no longer declares is reported as undeclared" {
  mkdir -p "$SANDBOX/dotfiles/home"
  cat >"$SANDBOX/dotfiles/home/.zshrc" <<'EOF'
zfetch zsh-users/zsh-completions
zfetch MichaelAquilina/zsh-you-should-use you-should-use.plugin.zsh
EOF
  # two declared clones present, plus one orphan (removed from .zshrc, clone lingers — #20)
  mkdir -p "$SANDBOX/plugins/zsh-users/zsh-completions/.git" \
    "$SANDBOX/plugins/MichaelAquilina/zsh-you-should-use/.git" \
    "$SANDBOX/plugins/grigorii-zander/zsh-npm-scripts-autocomplete/.git"

  plugins_undeclared
  [ "$status" -eq 0 ]
  [[ "$output" == *"grigorii-zander/zsh-npm-scripts-autocomplete"* ]] # orphan reported
  [[ "$output" != *"zsh-users/zsh-completions"* ]]                    # declared ones are not
  [[ "$output" != *"MichaelAquilina/zsh-you-should-use"* ]]
}

@test "plugins: no orphans when every clone is declared" {
  mkdir -p "$SANDBOX/dotfiles/home"
  printf 'zfetch zsh-users/zsh-completions\n' >"$SANDBOX/dotfiles/home/.zshrc"
  mkdir -p "$SANDBOX/plugins/zsh-users/zsh-completions/.git"

  plugins_undeclared
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---- brew domain ----
brew_undeclared() {
  run env DOTFILES="$SANDBOX/dotfiles" REPO="$REPO" bash -c '
    source "$REPO/bin/lib/common.sh"
    source "$REPO/bin/lib/reconcile.sh"
    dot_profile() { echo personal; }
    dot_docker_runtime() { echo docker-desktop; }
    brew() {
      case "$1 $2" in
        "leaves ") printf "%s\n" git ripgrep terraform-docs htop ;;
        "list --cask") printf "%s\n" docker-desktop aerospace ;;
      esac
    }
    reconcile_brew_undeclared
  '
}

@test "brew: only packages in no Brewfile (and not the docker runtime) are undeclared" {
  mkdir -p "$SANDBOX/dotfiles/brew"
  printf "brew 'git'\n" >"$SANDBOX/dotfiles/brew/Brewfile.core"
  printf "brew 'ripgrep'\n" >"$SANDBOX/dotfiles/brew/Brewfile.personal"
  printf "brew 'terraform-docs'\n" >"$SANDBOX/dotfiles/brew/Brewfile.work"

  brew_undeclared
  [ "$status" -eq 0 ]
  # truly-undeclared (installed, in no Brewfile) are reported
  [[ "$output" == *"htop"* ]]
  [[ "$output" == *"aerospace"* ]]
  # core / active-profile / other-profile / docker-runtime are NOT flagged
  [[ "$output" != *"git"* ]]            # core
  [[ "$output" != *"ripgrep"* ]]        # active profile (personal)
  [[ "$output" != *"terraform-docs"* ]] # declared elsewhere (work)
  [[ "$output" != *"docker-desktop"* ]] # config-driven docker runtime
}

# ---- sdkman domain ----
sdkman_undeclared() {
  run env DOTFILES="$SANDBOX/dotfiles" SDKMAN_DIR="$SANDBOX/.sdkman" REPO="$REPO" bash -c '
    source "$REPO/bin/lib/reconcile.sh"
    reconcile_sdkman_undeclared
  '
}

# ---- missing direction (declared but not installed) ----
@test "brew: a declared package that is installed only as a dependency is NOT missing" {
  mkdir -p "$SANDBOX/dotfiles/brew"
  printf "brew 'git'\nbrew 'python'\nbrew 'absent-tool'\n" >"$SANDBOX/dotfiles/brew/Brewfile.core"
  run env DOTFILES="$SANDBOX/dotfiles" REPO="$REPO" bash -c '
    source "$REPO/bin/lib/common.sh"
    source "$REPO/bin/lib/reconcile.sh"
    dot_profile() { echo personal; }
    dot_docker_runtime() { echo docker-desktop; }
    brew() {
      case "$1 ${2:-}" in
        "leaves ") printf "%s\n" git ;;                      # python is a dep, not a leaf
        "list --formula") printf "%s\n" git python ;;        # ...but it IS installed
        "list --cask") printf "%s\n" docker-desktop ;;
      esac
    }
    reconcile_brew_missing
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"absent-tool"* ]] # truly missing
  [[ "$output" != *"python"* ]]      # installed as dep — not missing
  [[ "$output" != *"git"* ]]
}

@test "summary: per-domain drift counts on one line each" {
  mkdir -p "$SANDBOX/dotfiles/home" "$SANDBOX/dotfiles/sdkman" "$SANDBOX/dotfiles/brew" "$SANDBOX/dotfiles/config"
  printf 'zfetch a/b\n' >"$SANDBOX/dotfiles/home/.zshrc"
  printf 'gradle\n' >"$SANDBOX/dotfiles/sdkman/toolchain"
  : >"$SANDBOX/dotfiles/brew/Brewfile.core"
  mkdir -p "$SANDBOX/plugins/c/d/.git" # one orphan plugin clone
  run env DOTFILES="$SANDBOX/dotfiles" ZPLUGDIR="$SANDBOX/plugins" \
    SDKMAN_DIR="$SANDBOX/.sdkman" HOME="$SANDBOX/home" REPO="$REPO" bash -c '
    source "$REPO/bin/lib/common.sh"
    source "$REPO/bin/lib/reconcile.sh"
    dot_profile() { echo personal; }
    dot_docker_runtime() { echo docker-desktop; }
    brew() { :; }
    reconcile_summary
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"plugins"*"1 undeclared"* ]] # the orphan clone
  [[ "$output" == *"sdkman"*"1 missing"* ]]     # gradle declared, none installed
}

# ---- dot-reconcile driver ----
setup_driver_fixture() {
  mkdir -p "$SANDBOX/bin" "$SANDBOX/home/.config" "$SANDBOX/dotfiles/brew" \
    "$SANDBOX/dotfiles/sdkman" "$SANDBOX/dotfiles/home" "$SANDBOX/dotfiles/config"
  printf "brew 'git'\n" >"$SANDBOX/dotfiles/brew/Brewfile.core"
  printf 'gradle\n' >"$SANDBOX/dotfiles/sdkman/toolchain"
  printf 'zfetch a/b\n' >"$SANDBOX/dotfiles/home/.zshrc"
  mkdir -p "$SANDBOX/plugins/c/orphan/.git"                   # orphan plugin clone
  cat >"$SANDBOX/bin/brew" <<'EOF'
#!/bin/bash
case "$1 ${2:-}" in
  "leaves ") printf '%s\n' git htop ;;
  "list --formula") printf '%s\n' git htop ;;
  "list --cask") : ;;
esac
EOF
  chmod +x "$SANDBOX/bin/brew"
}

run_driver() {
  run env PATH="$SANDBOX/bin:/usr/bin:/bin" HOME="$SANDBOX/home" \
    XDG_CONFIG_HOME="$SANDBOX/home/.config" DOTFILES="$SANDBOX/dotfiles" \
    ZPLUGDIR="$SANDBOX/plugins" SDKMAN_DIR="$SANDBOX/.sdkman" TERM=dumb \
    bash "$REPO/bin/dot-reconcile" "$@"
}

@test "driver: full report covers all domains and their drift" {
  setup_driver_fixture
  run_driver
  [ "$status" -eq 0 ]
  [[ "$output" == *"Homebrew"* && "$output" == *"htop"* ]]  # undeclared brew leaf
  [[ "$output" == *"SDKMAN"* && "$output" == *"gradle"* ]]  # missing declared candidate
  [[ "$output" == *"plugins"* && "$output" == *"c/orphan"* ]]
  [[ "$output" == *"Symlinks"* && "$output" == *".zshrc"* ]] # declared home file unlinked
}

@test "driver: scoping to one domain reports only that domain" {
  setup_driver_fixture
  run_driver brew
  [ "$status" -eq 0 ]
  [[ "$output" == *"htop"* ]]
  [[ "$output" != *"c/orphan"* && "$output" != *"SDKMAN"* ]]
}

@test "driver: --help documents domains and exits 0; unknown domain fails" {
  run_driver --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew"* && "$output" == *"symlinks"* ]]
  run_driver nonsense
  [ "$status" -ne 0 ]
}

# ---- symlinks domain (report-only) ----
symlinks_env() {
  env HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/home/.config" \
    DOTFILES="$SANDBOX/dotfiles" REPO="$REPO" bash -c '
    source "$REPO/bin/lib/common.sh"
    source "$REPO/bin/lib/reconcile.sh"
    '"$1"'
  '
}

# Fixture: a git-tracked dotfiles repo where home/.claude/settings.json existed,
# was linked into $HOME, then was deleted from the repo (the #21 case) — leaving
# a dangling link that derives from git history, not from current repo files.
setup_symlink_fixture() {
  mkdir -p "$SANDBOX/dotfiles/config/demo" "$SANDBOX/dotfiles/home/.claude" \
    "$SANDBOX/home/.config" "$SANDBOX/home/.claude"
  printf 'demo\n' >"$SANDBOX/dotfiles/config/demo/demo.conf"
  printf 'rc\n' >"$SANDBOX/dotfiles/home/.demorc"
  printf '{}\n' >"$SANDBOX/dotfiles/home/.claude/settings.json"
  git -C "$SANDBOX/dotfiles" init -q
  git -C "$SANDBOX/dotfiles" -c user.email=t@t -c user.name=t add -A
  git -C "$SANDBOX/dotfiles" -c user.email=t@t -c user.name=t commit -qm init
  # link the home file, then delete its source from the repo
  ln -s "$SANDBOX/dotfiles/home/.claude/settings.json" "$SANDBOX/home/.claude/settings.json"
  git -C "$SANDBOX/dotfiles" rm -q home/.claude/settings.json
  git -C "$SANDBOX/dotfiles" -c user.email=t@t -c user.name=t commit -qm "remove claude"
}

@test "symlinks: a dangling link whose repo source was deleted is reported (git-history derived)" {
  setup_symlink_fixture
  run symlinks_env reconcile_symlinks_dangling
  [ "$status" -eq 0 ]
  [[ "$output" == *".claude/settings.json"* ]]
}

@test "symlinks: declared-but-missing links are reported with their state" {
  setup_symlink_fixture
  run symlinks_env reconcile_symlinks_missing
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing"*"demo"* ]]    # config package never linked
  [[ "$output" == *"missing"*".demorc"* ]] # home file never linked
}

@test "symlinks: a healthy link is neither dangling nor missing" {
  setup_symlink_fixture
  mkdir -p "$SANDBOX/home/.config"
  ln -s "$SANDBOX/dotfiles/config/demo" "$SANDBOX/home/.config/demo"
  ln -s "$SANDBOX/dotfiles/home/.demorc" "$SANDBOX/home/.demorc"
  run symlinks_env 'reconcile_symlinks_dangling; reconcile_symlinks_missing'
  [ "$status" -eq 0 ]
  [[ "$output" != *"demo"* ]]
  [[ "$output" != *".demorc"* ]]
}

@test "sdkman: an installed candidate the toolchain does not declare is undeclared" {
  mkdir -p "$SANDBOX/dotfiles/sdkman"
  cat >"$SANDBOX/dotfiles/sdkman/toolchain" <<'EOF'
# toolchain
gradle
kotlin
java latest default
java 21
EOF
  mkdir -p "$SANDBOX/.sdkman/candidates/gradle/8.5" \
    "$SANDBOX/.sdkman/candidates/kotlin/2.0" \
    "$SANDBOX/.sdkman/candidates/java/21.0.1-tem" \
    "$SANDBOX/.sdkman/candidates/scala/3.4"

  sdkman_undeclared
  [ "$status" -eq 0 ]
  [[ "$output" == *"scala"* ]] # ad-hoc `sdk install scala` → undeclared
  [[ "$output" != *"gradle"* ]]
  [[ "$output" != *"kotlin"* ]]
  [[ "$output" != *"java"* ]]
}
