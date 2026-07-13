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
# Every brew test pins HOMEBREW_CACHE into the sandbox so the real machine's
# alias map (api/formula_aliases.txt) can never leak into a fixture.
brew_undeclared() {
  run env DOTFILES="$SANDBOX/dotfiles" HOMEBREW_CACHE="$SANDBOX/brew-cache" REPO="$REPO" bash -c '
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
  run env DOTFILES="$SANDBOX/dotfiles" HOMEBREW_CACHE="$SANDBOX/brew-cache" REPO="$REPO" bash -c '
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

# ---- name-alias normalization (#26) ----
# Brewfiles may declare a formula by an alias (kubectl) while brew lists the
# canonical name (kubernetes-cli); without normalization each aliased entry is
# double-reported as missing AND undeclared.

# Fixture: kubectl/python/golang declared as aliases; canonical names installed.
setup_alias_fixture() {
  mkdir -p "$SANDBOX/dotfiles/brew"
  printf "brew 'kubectl'\nbrew 'python'\n" >"$SANDBOX/dotfiles/brew/Brewfile.core"
  printf "brew 'golang'\n" >"$SANDBOX/dotfiles/brew/Brewfile.work" # declared elsewhere
}

# The injected fake brew: only canonical names installed, plus the runtime cask.
FAKE_BREW_CANONICAL='brew() {
  case "$1 ${2:-}" in
    "leaves ") printf "%s\n" kubernetes-cli python@3.14 go ;;
    "list --formula") printf "%s\n" kubernetes-cli python@3.14 go ;;
    "list --cask") printf "%s\n" docker-desktop ;;
    "--repository ") echo "$SANDBOX/brewrepo" ;;
  esac
}'

alias_report() {
  run env DOTFILES="$SANDBOX/dotfiles" HOMEBREW_CACHE="$SANDBOX/brew-cache" REPO="$REPO" bash -c '
    source "$REPO/bin/lib/common.sh"
    source "$REPO/bin/lib/reconcile.sh"
    dot_profile() { echo personal; }
    dot_docker_runtime() { echo docker-desktop; }
    '"$FAKE_BREW_CANONICAL"'
    reconcile_brew_undeclared
    reconcile_brew_missing
  '
}

@test "brew: an alias declared in a Brewfile matches its installed canonical name (API cache map)" {
  setup_alias_fixture
  mkdir -p "$SANDBOX/brew-cache/api"
  printf 'kubectl|kubernetes-cli\npython|python@3.14\ngolang|go\n' \
    >"$SANDBOX/brew-cache/api/formula_aliases.txt"

  alias_report
  [ "$status" -eq 0 ]
  # kubectl→kubernetes-cli, python→python@3.14 (declared), golang→go (declared
  # elsewhere): nothing is missing, nothing is undeclared — no false pairs.
  [ -z "$output" ]
}

@test "brew: alias map falls back to the local homebrew-core tap Aliases dir" {
  setup_alias_fixture
  # no API cache; a tapped homebrew-core provides Aliases/<alias> -> canonical .rb
  local aliases="$SANDBOX/brewrepo/Library/Taps/homebrew/homebrew-core/Aliases"
  mkdir -p "$aliases"
  ln -s ../Formula/kubernetes-cli.rb "$aliases/kubectl"
  ln -s ../Formula/python@3.14.rb "$aliases/python"
  ln -s ../Formula/go.rb "$aliases/golang"

  alias_report
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "brew: without alias data the diff degrades to unnormalized names (day-0/CI)" {
  setup_alias_fixture # neither API cache nor tap Aliases dir exists

  alias_report
  [ "$status" -eq 0 ]
  # the known #26 false pair is back — degraded, but never wrong about installs
  [[ "$output" == *"kubernetes-cli"* ]] # undeclared (canonical spelling)
  [[ "$output" == *"kubectl"* ]]        # missing (declared spelling)
}

@test "brew: cask tokens are never rewritten by the formula alias map" {
  mkdir -p "$SANDBOX/dotfiles/brew" "$SANDBOX/brew-cache/api"
  printf "cask 'foo'\n" >"$SANDBOX/dotfiles/brew/Brewfile.core"
  # a formula alias that collides with the declared cask token
  printf 'foo|bar\n' >"$SANDBOX/brew-cache/api/formula_aliases.txt"
  run env DOTFILES="$SANDBOX/dotfiles" HOMEBREW_CACHE="$SANDBOX/brew-cache" REPO="$REPO" bash -c '
    source "$REPO/bin/lib/common.sh"
    source "$REPO/bin/lib/reconcile.sh"
    dot_profile() { echo personal; }
    dot_docker_runtime() { echo docker-desktop; }
    brew() {
      case "$1 ${2:-}" in
        "list --cask") printf "%s\n" foo docker-desktop ;;
        *) : ;;
      esac
    }
    reconcile_brew_undeclared
    reconcile_brew_missing
  '
  [ "$status" -eq 0 ]
  # cask foo is declared and installed: normalizing it to bar would fabricate
  # a foo-undeclared + bar-missing pair
  [ -z "$output" ]
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
    DOT_TEST_DOTFILES="$SANDBOX/dotfiles" \
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

# ---- report rendering ----
@test "report: section hints render ANSI colors, never literal escape text (#36)" {
  # colors are backslash-text needing %b; force them on (bats has no tty)
  run bash -c '
    export SETUP_COLORS_COMPLETE=1
    DIM="\033[2m" RESET="\033[0m" YELLOW="\033[33m"
    source "'"$REPO"'/bin/dot-reconcile"
    printf "item\n" | _section "$YELLOW" "label" "→ dot homebrew bundle"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[2m'* ]] # real escape byte
  [[ "$output" != *'\033'* ]]     # never the 4-char literal
}

# ---- Brewfile OS conditionals (#37) ----
# Entries inside `if OS.mac?` / `elsif OS.linux?` blocks are declared only for
# that OS; a flat grep counts them everywhere (false "missing: xclip" on macOS).
setup_os_block_fixture() {
  mkdir -p "$SANDBOX/dotfiles/brew"
  cat >"$SANDBOX/dotfiles/brew/Brewfile.core" <<'BREWFILE'
if OS.mac?
  brew 'mac-only'
  cask 'mac-cask'
elsif OS.linux?
  brew 'xclip'
end
brew 'everywhere'
BREWFILE
}

os_block_missing() {
  run env DOTFILES="$SANDBOX/dotfiles" HOMEBREW_CACHE="$SANDBOX/brew-cache" REPO="$REPO" bash -c '
    source "$REPO/bin/lib/common.sh"
    source "$REPO/bin/lib/reconcile.sh"
    dot_profile() { echo personal; }
    dot_docker_runtime() { echo docker-desktop; }
    brew() { :; } # nothing installed
    uname() { echo '"$1"'; }
    reconcile_brew_missing
  '
}

@test "brew: a linux-only Brewfile entry is not missing on macOS" {
  setup_os_block_fixture
  os_block_missing Darwin
  [ "$status" -eq 0 ]
  [[ "$output" == *"mac-only"* && "$output" == *"mac-cask"* ]]
  [[ "$output" == *"everywhere"* ]]
  [[ "$output" != *"xclip"* ]] # linux branch — not declared here
}

@test "brew: a mac-only Brewfile entry is not missing on Linux" {
  setup_os_block_fixture
  os_block_missing Linux
  [ "$status" -eq 0 ]
  [[ "$output" == *"xclip"* && "$output" == *"everywhere"* ]]
  [[ "$output" != *"mac-only"* && "$output" != *"mac-cask"* ]]
}

# ---- doctor's cut of the declared set (#42) ----
# Doctor's tool checklist needs formulas for THIS OS in their declared spelling:
# no casks (a cask is an app, not a binary to probe) and no alias
# canonicalization (doctor's brew_cmd_for keys on the declared spelling).
declared_formulas() {
  run env DOTFILES="$SANDBOX/dotfiles" HOMEBREW_CACHE="$SANDBOX/brew-cache" REPO="$REPO" bash -c '
    source "$REPO/bin/lib/common.sh"
    source "$REPO/bin/lib/reconcile.sh"
    dot_profile() { echo personal; }
    dot_docker_runtime() { echo docker-desktop; }
    uname() { echo '"$1"'; }
    reconcile_brew_declared_formulas
  '
}

@test "brew: declared formulas keep spelling, drop casks, respect OS blocks" {
  mkdir -p "$SANDBOX/dotfiles/brew" "$SANDBOX/brew-cache/api"
  # Alias map present: set-diffs canonicalize kubectl -> kubernetes-cli; this cut must not.
  printf 'kubectl|kubernetes-cli\n' >"$SANDBOX/brew-cache/api/formula_aliases.txt"
  cat >"$SANDBOX/dotfiles/brew/Brewfile.core" <<'BREWFILE'
brew 'kubectl'
brew 'tflint-ruby/tflint/tflint'
cask 'ghostty'
if OS.mac?
  brew 'mac-only'
elsif OS.linux?
  brew 'xclip'
end
BREWFILE
  declared_formulas Darwin
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubectl"* ]]                   # declared spelling...
  [[ "$output" != *"kubernetes-cli"* ]]            # ...never canonicalized
  [[ "$output" == *"tflint-ruby/tflint/tflint"* ]] # tap-qualified intact
  [[ "$output" == *"mac-only"* ]]                  # active OS branch kept
  [[ "$output" != *"xclip"* ]]                     # other OS branch dropped
  [[ "$output" != *"ghostty"* ]]                   # casks excluded
  [[ "$output" != *"docker-desktop"* ]]            # injected runtime cask excluded
}
