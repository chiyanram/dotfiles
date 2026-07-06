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
