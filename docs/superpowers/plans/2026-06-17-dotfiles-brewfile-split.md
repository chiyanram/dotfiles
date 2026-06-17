# Dotfiles Brewfile Split — Implementation Plan (Plan 3 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the single `Brewfile` into profile-scoped bundles (`brew/Brewfile.{core,personal,work}`) and make `dot homebrew bundle` and `dot doctor` profile-aware, so a blocked work cask never stops core CLI installs and the Docker runtime is profile-defaulted but overridable.

**Architecture:** A `brew/` directory holds three bundles. Core has every cross-profile package; `personal`/`work` hold profile-specific apps (placeholders for now — filled in Plan 6). The Docker runtime is NOT in any bundle file — it's resolved at bundle time from `dot_config docker_runtime` (override) or the profile default (personal→`docker-desktop`, work→`rancher`). Three pure helpers in `common.sh` (`dot_brewfiles`, `dot_docker_runtime`, `dot_docker_runtime_entries`) are the single source of truth, consumed by both `dot-homebrew` and `dot-doctor` and unit-tested in isolation.

**Tech Stack:** bash, Homebrew Bundle, Ruby (Brewfile syntax check), bats-core.

## Global Constraints

Copied verbatim from the spec (`docs/superpowers/specs/2026-06-17-dotfiles-hardening-design.md` §5.2) and `CLAUDE.md`.

- macOS-only target; Apple Silicon `/opt/homebrew` with Intel fallback. Linux CI is a test substrate only.
- All bash scripts: `set -Eeuo pipefail`, source `$DOTFILES/bin/lib/common.sh`, `return 1` not `exit 1` in functions, no `trap EXIT` in functions, BSD-tool-safe.
- `dot-*` scripts: `# Description:` on line 2; `log_*`/`fmt_*` helpers; shfmt -i 2 -ci; shellcheck-clean (the gate covers `bin/dot`, every `bin/dot-*`, `bin/lib/*.sh`, `setup.sh`, `bootstrap.sh`).
- Brewfile rules: organized by category with comments; `cask` entries inside an `if OS.mac?` block; every entry has a trailing comment explaining what it is; no deprecated taps.
- Docker runtime: profile default is personal→`docker-desktop`, work→`rancher`; override via the `docker_runtime` config key (`docker-desktop` | `rancher` | `colima`); the matching brew entry is selected at bundle time.
- Profile/config helpers (`dot_profile`, `dot_config`) already exist in `common.sh` (Plan 2).
- Conventional Commits; imperative, lowercase, ≤72 chars. No `Co-Authored-By`.
- `bin/dot test` and CI (`checks` + `pre-commit`) must stay green.

---

## Plan Roadmap (where this fits)

Plans 1 (foundation) and 2 (profile system) are merged. This is Plan 3 — the first consumer of the profile spine. Deferred:
- `setup.sh` choosing the profile + persisting `docker_runtime` on a fresh machine → Plan 4 (resilient installer). Plan 3 does NOT touch `setup.sh`; the bundle defaults to `personal` when no profile is set, so a fresh personal machine behaves exactly as before (installs `docker-desktop`). A work machine runs `dot profile set work` first.
- Profile-aware doctor that verifies the Docker *runtime* itself → Plan 4. Plan 3 only updates doctor's Brewfile *source* so it keeps working after the move.

---

## File Structure (Plan 3)

- `brew/Brewfile.core` — **Create**: every cross-profile package (the current Brewfile minus the `docker-desktop` cask).
- `brew/Brewfile.personal` — **Create**: personal-only apps (header + placeholder; Docker runtime is resolved separately).
- `brew/Brewfile.work` — **Create**: work-only apps (header + placeholder).
- `Brewfile` — **Remove**: replaced by the `brew/` bundles.
- `bin/lib/common.sh` — **Modify**: add `dot_brewfiles`, `dot_docker_runtime`, `dot_docker_runtime_entries`.
- `.gitignore` — **Modify**: ignore `brew/*.lock.json`.
- `bin/dot-homebrew` — **Modify**: `homebrew_bundle` runs core + profile + resolved Docker runtime.
- `bin/dot-doctor` — **Modify**: derive tool checks from `dot_brewfiles` instead of the removed `$DOTFILES/Brewfile`.
- `tests/brew_helpers.bats` — **Create**: unit tests for the three helpers.
- `tests/brewfiles.bats` — **Create**: `ruby -c` syntax validation of the `brew/Brewfile.*` files.
- `CLAUDE.md`, `README.md` — **Modify**: update `Brewfile` references to the `brew/` layout.

---

## Task 1: Split the Brewfile and add the bundle-resolution helpers

Create the `brew/` bundles, remove the top-level `Brewfile`, add the three pure helpers to `common.sh`, and cover both the helpers and the Brewfile syntax with bats. This task's deliverable is "the new Brewfile layout and the tested logic to read it."

**Files:**
- Create: `brew/Brewfile.core`, `brew/Brewfile.personal`, `brew/Brewfile.work`
- Remove: `Brewfile`
- Modify: `bin/lib/common.sh`, `.gitignore`, `CLAUDE.md`, `README.md`
- Create: `tests/brew_helpers.bats`, `tests/brewfiles.bats`

**Interfaces:**
- Produces (from `common.sh`):
  - `dot_brewfiles [profile]` → prints `$DOTFILES/brew/Brewfile.core`, then `$DOTFILES/brew/Brewfile.<profile>` if it exists (profile defaults to `dot_profile`).
  - `dot_docker_runtime` → prints the resolved runtime: `dot_config docker_runtime` if set, else `rancher` for the `work` profile, else `docker-desktop`.
  - `dot_docker_runtime_entries <runtime>` → prints the brew-bundle line(s) for a runtime (`docker-desktop`→`cask 'docker-desktop'`, `rancher`→`cask 'rancher'`, `colima`→`brew 'colima'` + `brew 'docker'`); returns 1 for an unknown runtime.

- [ ] **Step 1: Write the failing helper tests**

Create `tests/brew_helpers.bats`:

```bash
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export DOTFILES="$SANDBOX/dotfiles"
  export TERM=dumb
  mkdir -p "$DOTFILES/brew"
  printf "brew 'git'\n" >"$DOTFILES/brew/Brewfile.core"
  printf "# personal\n" >"$DOTFILES/brew/Brewfile.personal"
  printf "# work\n" >"$DOTFILES/brew/Brewfile.work"
  source "$REPO/bin/lib/common.sh"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "dot_brewfiles defaults to core + personal when profile unset" {
  run dot_brewfiles
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"/brew/Brewfile.core" ]]
  [[ "${lines[1]}" == *"/brew/Brewfile.personal" ]]
}

@test "dot_brewfiles work returns core + work" {
  run dot_brewfiles work
  [[ "${lines[0]}" == *"/brew/Brewfile.core" ]]
  [[ "${lines[1]}" == *"/brew/Brewfile.work" ]]
}

@test "dot_brewfiles omits a missing profile file" {
  rm -f "$DOTFILES/brew/Brewfile.work"
  run dot_brewfiles work
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"/brew/Brewfile.core" ]]
}

@test "dot_docker_runtime defaults to docker-desktop for personal" {
  run dot_docker_runtime
  [ "$output" = "docker-desktop" ]
}

@test "dot_docker_runtime defaults to rancher for work" {
  dot_set_profile work
  run dot_docker_runtime
  [ "$output" = "rancher" ]
}

@test "dot_docker_runtime honors the config override" {
  dot_set_profile work
  dot_set_config docker_runtime colima
  run dot_docker_runtime
  [ "$output" = "colima" ]
}

@test "dot_docker_runtime_entries maps docker-desktop and rancher" {
  run dot_docker_runtime_entries docker-desktop
  [ "$output" = "cask 'docker-desktop'" ]
  run dot_docker_runtime_entries rancher
  [ "$output" = "cask 'rancher'" ]
}

@test "dot_docker_runtime_entries colima includes the docker cli" {
  run dot_docker_runtime_entries colima
  [[ "$output" == *"brew 'colima'"* ]]
  [[ "$output" == *"brew 'docker'"* ]]
}

@test "dot_docker_runtime_entries rejects an unknown runtime" {
  run dot_docker_runtime_entries frobnicate
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run the helper tests to verify they fail**

Run: `bats tests/brew_helpers.bats`
Expected: failures — the three helpers are not defined yet.

- [ ] **Step 3: Add the helpers to `common.sh`**

In `bin/lib/common.sh`, add this block immediately after the Profile / machine config section (before the final `setup_colors` call):

```bash
########################################################
# Homebrew profile bundles
########################################################

# Print the Brewfile paths for the active (or given) profile: core, then the
# profile-specific file if it exists.
dot_brewfiles() {
  local profile="${1:-$(dot_profile)}" dir
  dir="${DOTFILES:?DOTFILES must be set}/brew"
  printf '%s\n' "$dir/Brewfile.core"
  [[ -f "$dir/Brewfile.$profile" ]] && printf '%s\n' "$dir/Brewfile.$profile"
  return 0
}

# Resolve the Docker runtime: the docker_runtime config override, else the
# profile default (work -> rancher, otherwise docker-desktop).
dot_docker_runtime() {
  local runtime
  runtime="$(dot_config docker_runtime)"
  if [[ -z "$runtime" ]]; then
    case "$(dot_profile)" in
      work) runtime="rancher" ;;
      *) runtime="docker-desktop" ;;
    esac
  fi
  printf '%s\n' "$runtime"
}

# Print the brew-bundle entry/entries for a Docker runtime; return 1 if unknown.
dot_docker_runtime_entries() {
  case "${1:-}" in
    docker-desktop) printf "%s\n" "cask 'docker-desktop'" ;;
    rancher) printf "%s\n" "cask 'rancher'" ;;
    colima) printf "%s\n%s\n" "brew 'colima'" "brew 'docker'" ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 4: Run the helper tests to verify they pass**

Run: `bats tests/brew_helpers.bats`
Expected: `9 tests, 0 failures`.

- [ ] **Step 5: Create `brew/Brewfile.core`**

Create `brew/Brewfile.core` — every package from the current `Brewfile` EXCEPT the `docker-desktop` cask (which becomes runtime-resolved):

```ruby
# vim:ft=ruby
# Core packages — installed on every machine regardless of profile.

if OS.mac?
  # macOS utilities
  brew 'noti'                          # utility to display notifications from scripts
  brew 'trash'                         # rm, but put in the trash rather than completely delete

  # Applications (cross-profile)
  cask 'ghostty'                       # a better terminal emulator
  cask 'nikitabobko/tap/aerospace'     # a tiling window manager

  # Fonts
  cask 'font-symbols-only-nerd-font'   # nerd-only symbols font
elsif OS.linux?
  brew 'xclip'                         # access to clipboard (similar to pbcopy/pbpaste)
end

# Latest versions of some core utilities
brew 'git'                             # Git version control
brew 'bash'                            # bash shell
brew 'zsh'                             # zsh shell
brew 'grep'                            # grep

# Shell & navigation
brew 'starship'                        # cross-shell prompt
brew 'fzf'                             # Fuzzy file searcher, used in scripts and in vim
brew 'fd'                              # find alternative
brew 'ripgrep'                         # very fast file searcher
brew 'zoxide'                          # switch between most used directories
brew 'bat'                             # better cat
brew 'eza'                             # ls alternative
brew 'procs'                           # modern ps with color and tree view

# Development tools
brew 'neovim'                          # A better vim
brew 'tmux'                            # terminal multiplexer
brew 'sesh'                            # terminal session manager
brew 'lazygit'                         # a better git UI
brew 'gh'                              # GitHub CLI
brew 'git-delta'                       # a better git diff
brew 'entr'                            # file watcher / command runner
brew 'just'                            # project command runner (like make, but better)
brew 'direnv'                          # per-directory environment variables via .envrc
brew 'fnm'                             # Fast Node version manager
brew 'python'                          # python (latest)
brew 'stylua'                          # lua code formatter
brew 'shellcheck'                      # diagnostics for shell scripts
brew 'bats-core'                       # bash automated testing system (test harness)
brew 'shfmt'                           # shell script formatter (lint gate)
brew 'pre-commit'                      # git hook framework (runs shellcheck, gitleaks, etc.)
brew 'gitleaks'                        # secret scanner (pre-commit + CI)
brew 'glow'                            # terminal markdown viewer
brew 'jq'                              # work with JSON files in shell scripts
brew 'gnupg'                           # GPG
brew 'btop'                            # a top alternative

# Java / backend
brew 'jbang'                           # run Java source files as scripts without a project

# Infrastructure
brew 'yq'                              # jq for YAML — essential for K8s/Helm work
brew 'kubectl'                         # Kubernetes CLI
brew 'kubecolor'                       # colorized kubectl output
brew 'helm'                            # Kubernetes package manager
brew 'k9s'                             # Kubernetes TUI
brew 'kubectx'                         # fast Kubernetes context and namespace switching
brew 'stern'                           # multi-pod log tailing for Kubernetes
brew 'httpie'                          # better HTTP client
brew 'pgcli'                           # PostgreSQL CLI with autocomplete
brew 'dive'                            # Docker image layer analyzer
brew 'lazydocker'                      # Docker TUI (containers, images, volumes, logs)
```

- [ ] **Step 6: Create the profile bundles**

Create `brew/Brewfile.personal`:

```ruby
# vim:ft=ruby
# Personal-profile packages.
# The Docker runtime is installed separately by `dot homebrew bundle`
# (defaults to docker-desktop for personal; override with:
#   dot profile set-config docker_runtime <docker-desktop|rancher|colima>).
# Add personal-only apps here.
```

Create `brew/Brewfile.work`:

```ruby
# vim:ft=ruby
# Work-profile packages.
# The Docker runtime is installed separately by `dot homebrew bundle`
# (defaults to rancher for work; override with:
#   dot profile set-config docker_runtime <docker-desktop|rancher|colima>).
# Add corp-only tools here (VPN, Slack, company CLIs) as they are approved.
```

- [ ] **Step 7: Remove the old Brewfile and update `.gitignore`**

Run: `git rm Brewfile`

In `.gitignore`, find the Homebrew section line `Brewfile.lock.json` and add below it:

```gitignore
brew/*.lock.json
```

- [ ] **Step 8: Write the Brewfile syntax-validation test**

Create `tests/brewfiles.bats`:

```bash
setup() { REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"; }

@test "brew Brewfiles are valid ruby syntax" {
  command -v ruby >/dev/null || skip "ruby not installed"
  local f
  for f in "$REPO"/brew/Brewfile.*; do
    run ruby -c "$f"
    [ "$status" -eq 0 ]
  done
}
```

- [ ] **Step 9: Update the docs references**

In `CLAUDE.md`, update the `Brewfile` references to the new layout. The "Key Files" line `- \`Brewfile\` — all Homebrew packages (organized by category)` becomes:

```markdown
- `brew/Brewfile.core` — cross-profile Homebrew packages; `brew/Brewfile.{personal,work}` — profile-specific
```

In the Brewfile rules section, update the intro so the rules apply to `brew/Brewfile.*`. In `README.md`, update any `Brewfile` mention to `brew/Brewfile.*` (read the file first and match its style; if there is no such mention, skip).

- [ ] **Step 10: Run the full gate**

Run: `bats tests/brew_helpers.bats tests/brewfiles.bats`
Expected: all pass (9 helper tests + 1 syntax test).

Run: `bin/dot test`
Expected: `All checks passed`. If `shfmt` flags `common.sh`, run `shfmt -i 2 -ci -w bin/lib/common.sh` and re-run.

Run: `pre-commit run --all-files`
Expected: all hooks Passed/Skipped.

- [ ] **Step 11: Commit**

```bash
git add brew/ bin/lib/common.sh .gitignore tests/brew_helpers.bats tests/brewfiles.bats CLAUDE.md README.md
git rm --cached Brewfile 2>/dev/null || true
git commit -m "feat(brew): split Brewfile into profile bundles with resolution helpers"
```

(The `git rm Brewfile` in Step 7 already staged the deletion; the commit includes it.)

---

## Task 2: Profile-aware `dot homebrew bundle`

Rewrite `homebrew_bundle` to install core + the active profile's bundle + the resolved Docker runtime, using the Task 1 helpers.

**Files:**
- Modify: `bin/dot-homebrew`

**Interfaces:**
- Consumes: `dot_brewfiles`, `dot_docker_runtime`, `dot_docker_runtime_entries` from `common.sh`.

- [ ] **Step 1: Rewrite `homebrew_bundle`**

In `bin/dot-homebrew`, replace the body of `homebrew_bundle` (the current `brew bundle --file="$DOTFILES/Brewfile"` block) with a loop over `dot_brewfiles` plus the Docker runtime. The new function:

```bash
homebrew_bundle() {
  if ! command -v brew &>/dev/null; then
    log_error "Homebrew is not installed. Exiting."
    return 1
  fi

  fmt_title_underline "Installing Homebrew packages (profile: $(dot_profile))"

  local bf
  while IFS= read -r bf; do
    log_info "Bundling ${bf##*/}"
    if ! brew bundle --file="$bf"; then
      log_error "Failed bundling $bf"
      return 1
    fi
  done < <(dot_brewfiles)

  # Docker runtime — profile default, overridable via the docker_runtime config key.
  local runtime entries
  runtime="$(dot_docker_runtime)"
  if entries="$(dot_docker_runtime_entries "$runtime")"; then
    log_info "Docker runtime: $runtime"
    if ! brew bundle --file=<(printf '%s\n' "$entries"); then
      log_error "Failed installing Docker runtime: $runtime"
      return 1
    fi
  else
    log_warning "Unknown docker_runtime '$runtime' — skipping (set with: dot profile set-config docker_runtime <docker-desktop|rancher|colima>)"
  fi

  log_success "Homebrew packages installed successfully."

  # install fzf key bindings (only on first run)
  local fzf_install
  fzf_install="$(brew --prefix)/opt/fzf/install"
  if [[ -x "$fzf_install" ]] && [[ ! -f "$HOME/.fzf.zsh" ]]; then
    echo -e
    log_info "Installing fzf key bindings"
    "$fzf_install" --key-bindings --completion --no-update-rc --no-bash --no-fish
  fi
}
```

Note: this also changes the two `exit 1` calls in the old body to `return 1` (correct per the global constraints — `homebrew_bundle` is a function).

- [ ] **Step 2: Verify shellcheck/shfmt and syntax**

Run: `shellcheck -x bin/dot-homebrew && bash -n bin/dot-homebrew && shfmt -i 2 -ci -d bin/dot-homebrew && echo OK`
Expected: prints `OK` (no shellcheck/shfmt diffs). If shfmt complains, run `shfmt -i 2 -ci -w bin/dot-homebrew`.

- [ ] **Step 3: Dry-run the resolution without installing (sandbox)**

Run this to confirm the function resolves the right files/runtime for each profile WITHOUT invoking brew (it stops at the first `brew bundle` only if brew is present — so just verify the resolved plan via the helpers):

```bash
SBX=$(mktemp -d)
HOME="$SBX" XDG_CONFIG_HOME="$SBX/.config" DOTFILES="$PWD" bash -c '
  source "$PWD/bin/lib/common.sh"
  echo "personal files:"; dot_brewfiles personal
  echo "work runtime:"; dot_set_profile work; dot_docker_runtime
'
trash "$SBX"
```
Expected: personal lists `brew/Brewfile.core` + `brew/Brewfile.personal`; work runtime prints `rancher`.

- [ ] **Step 4: Run the full gate**

Run: `bin/dot test`
Expected: `All checks passed`.

- [ ] **Step 5: Commit**

```bash
git add bin/dot-homebrew
git commit -m "feat(brew): make dot homebrew bundle profile-aware"
```

---

## Task 3: Update `dot-doctor` to read the split bundles

`dot-doctor` derives its Homebrew tool checks by grepping `brew '...'` from `$DOTFILES/Brewfile`, which no longer exists. Point it at `dot_brewfiles` (core + active profile).

**Files:**
- Modify: `bin/dot-doctor`

- [ ] **Step 1: Replace the Brewfile-parsing block**

In `bin/dot-doctor` `main()`, replace this block (the `local brewfile=...` through its `else`/`fi`):

```bash
  local brewfile="$DOTFILES/Brewfile"
  if [[ -f "$brewfile" ]]; then
    while IFS= read -r formula; do
      [[ "$brew_skip" == *" $formula "* ]] && continue
      local cmd="${brew_cmd_map[$formula]:-$formula}"
      local required="false"
      [[ "$required_tools" == *" $formula "* ]] && required="true"
      check_tool "$formula" "$cmd" "$required"
    done < <(grep -E "^[[:space:]]*brew '" "$brewfile" | sed "s/.*brew '\\([^']*\\)'.*/\\1/")
  else
    log_warning "Brewfile not found at $brewfile"
  fi
```

with a version that reads every file from `dot_brewfiles`:

```bash
  local -a brewfiles=()
  local bf
  while IFS= read -r bf; do
    [[ -f "$bf" ]] && brewfiles+=("$bf")
  done < <(dot_brewfiles)

  if [[ "${#brewfiles[@]}" -gt 0 ]]; then
    while IFS= read -r formula; do
      [[ "$brew_skip" == *" $formula "* ]] && continue
      local cmd="${brew_cmd_map[$formula]:-$formula}"
      local required="false"
      [[ "$required_tools" == *" $formula "* ]] && required="true"
      check_tool "$formula" "$cmd" "$required"
    done < <(grep -hE "^[[:space:]]*brew '" "${brewfiles[@]}" | sed "s/.*brew '\\([^']*\\)'.*/\\1/")
  else
    log_warning "No Brewfiles found under $DOTFILES/brew/"
  fi
```

(`grep -h` suppresses the filename prefix when grepping multiple files; the array avoids unquoted word-splitting.)

- [ ] **Step 2: Verify shellcheck/shfmt/syntax**

Run: `shellcheck -x bin/dot-doctor && bash -n bin/dot-doctor && shfmt -i 2 -ci -d bin/dot-doctor && echo OK`
Expected: prints `OK`. If shfmt complains, run `shfmt -i 2 -ci -w bin/dot-doctor`.

- [ ] **Step 3: Smoke-test doctor finds the Homebrew packages**

Run: `DOTFILES="$PWD" ./bin/dot-doctor 2>&1 | sed -n '/Homebrew Packages/,/Java/p' | head -20`
Expected: the Homebrew Packages section lists real formulae (git, neovim, ripgrep, …) derived from `brew/Brewfile.core` — NOT a "No Brewfiles found" warning. (Individual tools may show installed or not-found depending on the machine; the point is the list is populated.)

- [ ] **Step 4: Run the full gate**

Run: `bin/dot test`
Expected: `All checks passed`.

Run: `pre-commit run --all-files`
Expected: all hooks Passed/Skipped.

- [ ] **Step 5: Commit**

```bash
git add bin/dot-doctor
git commit -m "feat(doctor): derive tool checks from profile brew bundles"
```

---

## Done criteria for Plan 3

- `brew/Brewfile.{core,personal,work}` exist; the top-level `Brewfile` is gone; `brew/*.lock.json` is gitignored.
- `dot_brewfiles` / `dot_docker_runtime` / `dot_docker_runtime_entries` are unit-covered (9 tests) and the bundles pass `ruby -c`.
- `dot homebrew bundle` installs core + the active profile's bundle + the resolved Docker runtime (personal→docker-desktop, work→rancher, override via `docker_runtime`); a blocked profile/runtime entry returns non-zero without aborting the core bundle that already ran.
- `dot doctor` lists Homebrew packages derived from the split bundles (no "Brewfile not found").
- `bin/dot test` and both CI jobs stay green. No `setup.sh` changes (profile selection at setup lands in Plan 4).
