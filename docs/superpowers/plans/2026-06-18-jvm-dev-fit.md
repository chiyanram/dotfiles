# JVM Polyglot Dev Fit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fit the shell + tooling to the owner's real polyglot-JVM profile (Java/Kotlin/Scala/Maven/Gradle/Testcontainers) — a language-aware starship prompt, Docker helpers that survive Testcontainers, per-project JDK auto-switching, and three missing power tools.

**Architecture:** Four independent layers, each a focused edit to an existing file (plus one new bats test): starship prompt, `.docker_aliases` helpers, SDKMAN auto-env (setup.sh + doctor + test), and Brewfile tools. No shared state — any order. Spec: `docs/superpowers/specs/2026-06-18-jvm-dev-fit-design.md`.

**Tech Stack:** starship (TOML), zsh/bash functions, SDKMAN, bats, Homebrew (Brewfile), Docker.

## Global Constraints

- macOS only, Apple Silicon. Conventional Commits; **no `Co-Authored-By`**.
- `.docker_aliases` is sourced by zsh — keep it bash/zsh-portable, BSD-safe (no GNU `sed -i`; macOS `sed -i ''` is fine). Never alias/shadow POSIX core commands.
- `bin/`/`setup.sh` keep `set -Eeuo pipefail`, `return 1` (not `exit 1`) in functions, no `trap EXIT` in functions, source `$DOTFILES/bin/lib/common.sh`, use `log_*` helpers. Edits to `~/.sdkman/etc/config` MUST be idempotent and `[[ -f ]]`-guarded.
- **`tc-clean` is destructive — it must be strictly label-scoped to `label=org.testcontainers=true` and never touch a non-Testcontainers resource.**
- `dctx` reads the `docker_runtime` config key from `~/.config/dotfiles/config` (consumer only); it does not hardcode a single runtime.
- Validation gates: `zsh -i -c 'echo ok'` clean; `bin/dot test` (runs shellcheck + bats over `tests/`) green; `pre-commit run --all-files` green. The shellcheck pre-commit gate covers `setup.sh` + `bin/` (not `home/.docker_aliases`).

## File structure

| File | Responsibility | Task |
|------|----------------|------|
| `config/starship/starship.toml` | Kotlin/Scala prompt modules; Java drops sbt-detection | 1 |
| `home/.docker_aliases` | fix 3 bugs; add `tc-ls`/`tc-clean`/`dctx` | 2 |
| `setup.sh` | idempotent `sdkman_auto_env=true` + source-guard | 3 |
| `bin/dot-doctor` | warn when sdkman auto-env is off | 3 |
| `tests/sdkman_autoenv.bats` (new) | unit-test the flip's idempotency | 3 |
| `brew/Brewfile.core` | add ktlint, async-profiler, jdk-mission-control | 4 |

---

## Task 1: starship Kotlin + Scala

**Files:** Modify `config/starship/starship.toml`

**Interfaces:** none consumed/produced.

- [ ] **Step 1: Add `$kotlin` and `$scala` to the format string**

In the `format = """..."""` block, the line is `$java\`. Insert two lines right after it:
```
$java\
$kotlin\
$scala\
$terraform\
```

- [ ] **Step 2: Remove `build.sbt` from the `[java]` module**

The `[java]` block's detect line is:
```
detect_files = ["pom.xml", "build.gradle", "build.gradle.kts", "build.sbt", ".java-version"]
```
Change it to (drop `build.sbt` so sbt projects show Scala, not Java):
```
detect_files = ["pom.xml", "build.gradle", "build.gradle.kts", ".java-version"]
```

- [ ] **Step 3: Re-enable + style the `[kotlin]` module**

Replace this block:
```
# ─── Kotlin (disabled — no Kotlin in stack; lights up on Gradle-Kotlin projects) ──
[kotlin]
disabled = true
```
with (glyph + macchiato mauve, matching the `[java]` block's format shape):
```
# ─── Kotlin ───────────────────────────────────────
[kotlin]
format = '\[[ $version]($style)\] '
style = "bold #c6a0f6"
```

- [ ] **Step 4: Add the `[scala]` module**

Immediately after the `[kotlin]` block, add:
```
# ─── Scala ────────────────────────────────────────
[scala]
format = '\[[ $version]($style)\] '
style = "bold #ee99a0"
```
(The scala module auto-detects `build.sbt`/`.scala`/`.sc`/`.metals` by default — no `detect_files` needed.)

- [ ] **Step 5: Verify**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
python3 -c "import tomllib; tomllib.load(open('config/starship/starship.toml','rb')); print('toml ok')"
tmp=$(mktemp -d); (cd "$tmp" && touch build.sbt && STARSHIP_CONFIG="$DOTFILES/config/starship/starship.toml" starship module scala 2>&1 | grep -qi scala && echo "scala-shows-on-sbt" || echo "scala-module-empty")
(cd "$tmp" && touch build.sbt && STARSHIP_CONFIG="$DOTFILES/config/starship/starship.toml" starship module java 2>&1 | grep -qi 'java\|v[0-9]' && echo "java-STILL-shows-on-sbt (BUG)" || echo "java-correctly-hidden-on-sbt"); rm -rf "$tmp"
bin/dot test 2>&1 | tail -1
pre-commit run --all-files 2>&1 | tail -5
```
Expected: `toml ok`; `scala-shows-on-sbt` (if scala SDK present — if scala isn't on PATH the module is empty, which is acceptable, note it); `java-correctly-hidden-on-sbt`; `All checks passed`; hooks Passed. (The glyphs ``/`` should render in your Nerd Font; if either shows as a box, swap for a glyph that renders and note it.)

**Manual confirmation (owner):** `cd` into a Kotlin project → Kotlin badge; an sbt project → Scala badge (not Java); a Maven project → Java badge.

- [ ] **Step 6: Commit**
```bash
git add config/starship/starship.toml
git commit -m "feat(starship): kotlin + scala modules; java no longer claims sbt"
```

---

## Task 2: Docker bug fixes + Testcontainers helpers + dctx

**Files:** Modify `home/.docker_aliases`

**Interfaces:** `dctx` consumes the `docker_runtime` key from `~/.config/dotfiles/config` (read inline; the `dot_*` helpers in common.sh are NOT available in an interactive shell).

- [ ] **Step 1: Fix the three bugs**

`dip-fn` — add a `local` declaration so `OUT` isn't a global. The current function body starts:
```bash
function dip-fn {
  echo "IP addresses of all named running containers"

  for DOC in $(dnames-fn); do
```
Insert `local OUT=""` after the `echo` line:
```bash
function dip-fn {
  echo "IP addresses of all named running containers"
  local OUT=""

  for DOC in $(dnames-fn); do
```
and delete the now-redundant `unset OUT` line near the end of that function.

`drun-fn` — stop dropping args:
```bash
function drun-fn {
  docker run -it "$1" "$2"
}
```
→
```bash
function drun-fn {
  docker run -it "$@"
}
```

`d-aws-cli-fn` — stop dropping args. The last line:
```bash
    amazon/aws-cli:latest "$1" "$2" "$3"
```
→
```bash
    amazon/aws-cli:latest "$@"
```

- [ ] **Step 2: Add the Testcontainers + context helpers**

Add these three functions just before the `# Disabled aliases...` comment / alias block near the end of the file. They are defined with their final names (no `-fn`+alias indirection — that pattern exists only to abbreviate long names, which these don't need):
```bash
# Testcontainers: list leftover containers (label-scoped)
tc-ls() {
  command -v docker >/dev/null 2>&1 || { echo "docker not found"; return 1; }
  docker ps -a --filter "label=org.testcontainers=true" \
    --format 'table {{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Status}}'
}

# Testcontainers: remove ALL leftover containers/volumes/networks.
# Strictly label-scoped to org.testcontainers — never touches other resources.
tc-clean() {
  command -v docker >/dev/null 2>&1 || { echo "docker not found"; return 1; }
  local ids
  ids=$(docker ps -aq --filter "label=org.testcontainers=true")
  if [[ -n "$ids" ]]; then
    echo "$ids" | xargs docker rm -f
  else
    echo "no Testcontainers containers"
  fi
  docker volume prune -f --filter "label=org.testcontainers=true" >/dev/null
  docker network prune -f --filter "label=org.testcontainers=true" >/dev/null
}

# Docker context switch. No arg: show configured runtime + current + available.
# Arg: rancher|desktop|<context-name> → docker context use.
dctx() {
  command -v docker >/dev/null 2>&1 || { echo "docker not found"; return 1; }
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/config" configured=""
    [[ -f "$cfg" ]] && configured=$(grep -E '^docker_runtime=' "$cfg" 2>/dev/null | head -1 | cut -d= -f2)
    echo "configured runtime: ${configured:-<unset>}"
    echo "current context:    $(docker context show 2>/dev/null)"
    docker context ls
    return 0
  fi
  case "$target" in
    rancher|rancher-desktop) target="rancher-desktop" ;;
    desktop|docker-desktop)  target="desktop-linux" ;;
  esac
  docker context use "$target"
}
```

- [ ] **Step 3: Verify**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
shellcheck -s bash home/.docker_aliases || echo "(shellcheck warnings — fix real ones; SC2086 on intentional word-splitting may be acceptable, justify with a disable comment)"
zsh -ic 'source "$DOTFILES/home/.docker_aliases" && type tc-ls tc-clean dctx >/dev/null && echo "helpers-load-ok"'
zsh -ic 'source "$DOTFILES/home/.docker_aliases"; dctx' 2>&1 | head -3
zsh -i -c 'echo ok' 2>&1 | tail -1
bin/dot test 2>&1 | tail -1
pre-commit run --all-files 2>&1 | tail -5
```
Expected: shellcheck clean (or only justified disables); `helpers-load-ok`; `dctx` prints the configured runtime + current context + the context list (no error, no side effect); `ok`; `All checks passed`; hooks Passed.

**Manual confirmation (owner):** after a Testcontainers run, `tc-ls` shows the leftovers and `tc-clean` removes only those; `dctx rancher` / `dctx desktop` switch contexts; `drun <img> sh -c 'echo hi'` passes all args.

- [ ] **Step 4: Commit**
```bash
git add home/.docker_aliases
git commit -m "feat(docker): testcontainers tc-ls/tc-clean, dctx switcher; fix arg-dropping + local OUT"
```

---

## Task 3: SDKMAN per-project auto-env

**Files:** Modify `setup.sh`, `bin/dot-doctor`; Create `tests/sdkman_autoenv.bats`

**Interfaces:**
- Produces: `configure_sdkman_auto_env()` in `setup.sh` — idempotently ensures `sdkman_auto_env=true` in the file named by `${SDKMAN_CONFIG:-$HOME/.sdkman/etc/config}`. The `SDKMAN_CONFIG` override exists so the bats test can point it at a temp file.

- [ ] **Step 1: Write the failing bats test**

Create `tests/sdkman_autoenv.bats` (mirror the `load`/setup conventions of `tests/setup_dryrun.bats`). Each test runs the flip in an isolated subprocess — `run bash -c "source setup.sh; ..."` — so `setup.sh`'s `set -Eeuo pipefail` and its `main` guard can't interfere with bats, and the assertion is made on the temp file afterward:
```bash
#!/usr/bin/env bats

load test_helper

setup() {
  CFG="$BATS_TEST_TMPDIR/config"
  SETUP="$BATS_TEST_DIRNAME/../setup.sh"
}

@test "configure_sdkman_auto_env flips false to true" {
  printf 'sdkman_auto_answer=false\nsdkman_auto_env=false\n' > "$CFG"
  run bash -c "SDKMAN_CONFIG='$CFG'; source '$SETUP'; configure_sdkman_auto_env"
  [ "$status" -eq 0 ]
  grep -q '^sdkman_auto_env=true$' "$CFG"
}

@test "configure_sdkman_auto_env is idempotent (no duplicate keys)" {
  printf 'sdkman_auto_env=true\n' > "$CFG"
  run bash -c "SDKMAN_CONFIG='$CFG'; source '$SETUP'; configure_sdkman_auto_env"
  [ "$status" -eq 0 ]
  run grep -c '^sdkman_auto_env=' "$CFG"
  [ "$output" -eq 1 ]
}

@test "configure_sdkman_auto_env appends when the key is absent" {
  printf 'sdkman_auto_answer=false\n' > "$CFG"
  run bash -c "SDKMAN_CONFIG='$CFG'; source '$SETUP'; configure_sdkman_auto_env"
  [ "$status" -eq 0 ]
  grep -q '^sdkman_auto_env=true$' "$CFG"
}
```
(If `source setup.sh` fails because the script references an unset var at source time under `set -u`, export what it needs in the `bash -c` prefix — check how `tests/setup_dryrun.bats` invokes `setup.sh` and match it.)

- [ ] **Step 2: Run the test, confirm it fails**

Run: `cd /Users/chiyanram/tools-repo/dotfiles && bats tests/sdkman_autoenv.bats`
Expected: FAILS — either `configure_sdkman_auto_env: command not found`, or `source setup.sh` runs the installer (because the source-guard from Step 3 isn't in place yet).

- [ ] **Step 3: Add the source-guard + the function to `setup.sh`**

At the very bottom of `setup.sh`, change:
```bash
main "$@"
```
to:
```bash
# Only run main when executed directly (sourcing for tests must not install anything).
[[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && main "$@"
```

Add the function above `step_sdkman()` (it uses `log_success` from common.sh, already sourced by setup.sh):
```bash
configure_sdkman_auto_env() {
  local cfg="${SDKMAN_CONFIG:-$HOME/.sdkman/etc/config}"
  [[ -f "$cfg" ]] || return 0
  if grep -q '^sdkman_auto_env=true$' "$cfg"; then
    return 0
  elif grep -q '^sdkman_auto_env=' "$cfg"; then
    sed -i '' 's/^sdkman_auto_env=.*/sdkman_auto_env=true/' "$cfg"
  else
    printf 'sdkman_auto_env=true\n' >> "$cfg"
  fi
  log_success "SDKMAN auto-env enabled (.sdkmanrc auto-applies on cd)"
}
```

- [ ] **Step 4: Call it from `step_sdkman` (both paths)**

`step_sdkman()` returns early when SDKMAN is already installed. Call the configurator in BOTH the already-installed path and after a fresh install, so existing machines get the flip too.

In the already-installed branch:
```bash
  if [[ -d "$HOME/.sdkman" ]]; then
    log_success "SDKMAN already installed"
    configure_sdkman_auto_env
    return "$STEP_SKIP_CODE"
  fi
```
And just before the final `return 0` of `step_sdkman` (after the fresh install + `sdk install` prompts):
```bash
  configure_sdkman_auto_env
  return 0 # a declined optional install (ask_yes_no -> 1) must not fail the step
```

- [ ] **Step 5: Run the test, confirm it passes**

Run: `cd /Users/chiyanram/tools-repo/dotfiles && bats tests/sdkman_autoenv.bats`
Expected: all 3 tests PASS.

- [ ] **Step 6: Add the dot-doctor check**

In `bin/dot-doctor`, add a check function (mirror the `check_sdkman` style) — place it just after `check_sdkman`:
```bash
check_sdkman_env() {
  local cfg="${SDKMAN_DIR:-$HOME/.sdkman}/etc/config"
  [[ -f "$cfg" ]] || return 0
  if grep -q '^sdkman_auto_env=true$' "$cfg"; then
    printf "  %b %b%-14s%b %b%s%b\n" "${GREEN}${SUCCESS_ICON}" "$BOLD" "sdkman env" "$RESET" "$DIM" "auto-env on" "$RESET"
  else
    printf "  %b %b%-14s%b %b%s%b\n" "${YELLOW}${WARNING_ICON}" "$BOLD" "sdkman env" "$RESET" "$YELLOW" "auto-env off — run ./setup.sh to enable .sdkmanrc on cd" "$RESET"
    optional_missing=$((optional_missing + 1))
  fi
}
```
Register it immediately after the existing `check_sdkman` call (search for where `check_sdkman` is invoked in the run list) by adding `check_sdkman_env` on the next line.

- [ ] **Step 7: Apply it to this machine + verify**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
SDKMAN_CONFIG="$HOME/.sdkman/etc/config" bash -c 'source ./setup.sh; configure_sdkman_auto_env'
grep '^sdkman_auto_env=' ~/.sdkman/etc/config        # → sdkman_auto_env=true
bats tests/sdkman_autoenv.bats                        # 3 passing
bin/dot doctor 2>&1 | grep -i 'sdkman env'            # → green "auto-env on"
bin/dot test 2>&1 | tail -1
pre-commit run --all-files 2>&1 | tail -5
```
Expected: config shows `true`; 3 bats pass; doctor shows `auto-env on`; `All checks passed`; hooks Passed (shellcheck covers `setup.sh` + `bin/dot-doctor`).

- [ ] **Step 8: Commit**
```bash
git add setup.sh bin/dot-doctor tests/sdkman_autoenv.bats
git commit -m "feat(sdkman): auto-enable per-project env (.sdkmanrc on cd) with doctor check"
```

---

## Task 4: JVM power tools

**Files:** Modify `brew/Brewfile.core`

**Interfaces:** none.

- [ ] **Step 1: Add the two formulae + one cask**

Read `brew/Brewfile.core`. In the dev-tools section (near `brew 'jbang'` / `brew 'google-java-format'`), add:
```ruby
brew 'ktlint'                          # Kotlin linter/formatter (complements detekt)
brew 'async-profiler'                  # low-overhead JVM sampling profiler (flame graphs)
```
Inside the `if OS.mac?` cask block (where other `cask` entries live), add:
```ruby
  cask 'jdk-mission-control'           # GUI to analyze JFR recordings (pairs with jfr)
```

- [ ] **Step 2: Verify the Brewfile parses and the entries resolve**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
brew bundle list --file=brew/Brewfile.core 2>/dev/null | grep -E 'ktlint|async-profiler|jdk-mission-control' && echo "entries-present"
brew info ktlint >/dev/null 2>&1 && brew info async-profiler >/dev/null 2>&1 && brew info --cask jdk-mission-control >/dev/null 2>&1 && echo "all-resolve"
bin/dot test 2>&1 | tail -1
pre-commit run --all-files 2>&1 | tail -5
```
Expected: the three entries listed; `entries-present`; `all-resolve`; `All checks passed`; hooks Passed.

- [ ] **Step 3: Install them**

Run: `cd /Users/chiyanram/tools-repo/dotfiles && dot homebrew bundle` (the cask is a sizeable download — let it finish). Then:
```bash
command -v ktlint && command -v async-profiler && ls -d /Applications/JDK*Mission*Control*.app 2>/dev/null && echo "installed"
```
Expected: `installed`. If the bundle aborts on an unrelated tap (`tflint`/`tenv` need taps), that does not affect these three — confirm with the line above.

- [ ] **Step 4: Commit**
```bash
git add brew/Brewfile.core
git commit -m "feat(brew): add ktlint, async-profiler, jdk-mission-control"
```

---

## Done criteria
- starship shows Kotlin and Scala; a Scala/sbt project shows the Scala badge (not Java); `starship.toml` is valid; glyphs render.
- `.docker_aliases`: `drun`/`daws` pass all args, `dip` uses a `local`; `tc-ls`/`tc-clean` are label-scoped to `org.testcontainers=true`; `dctx` shows/switches context and reads `docker_runtime`. The file sources clean and shellcheck is satisfied.
- `sdkman_auto_env=true` is applied on this machine, the flip is idempotent (3 bats tests green), `dot doctor` reports `auto-env on`, and `.sdkmanrc` files auto-switch on `cd`.
- `ktlint`, `async-profiler`, `jdk-mission-control` are in `Brewfile.core` and installed.
- `bin/dot test` and `pre-commit run --all-files` stay green; four scoped commits.
