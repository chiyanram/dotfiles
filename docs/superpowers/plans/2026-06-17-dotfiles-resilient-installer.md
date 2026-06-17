# Dotfiles Resilient Installer — Implementation Plan (Plan 5 of 8)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `setup.sh` onto the Plan 4 step runner so a blocked MDM/proxy step never aborts the whole fresh-machine install — every step is non-fatal and re-runnable, the run always ends with a summary, and setup chooses + persists the machine profile (consuming the Plan 2/3 spine).

**Architecture:** `setup.sh` becomes a set of `step_*` functions (one per install phase) run through `step`/`step_summary`. Each returns `0` (ok), `STEP_SKIP_CODE` (already done / declined / not applicable), or `1` (failed). Flags `--profile`, `--non-interactive`, and `--dry-run` control prompting and previewing. A new profile step replaces the dead `HOMEBREW_DOCKER_RUNTIME` env var by persisting `profile` + `docker_runtime` via `dot profile`; the brew-bundle step is already profile-aware (Plan 3). Task 2 hardens the curl-piped installers (Homebrew, SDKMAN) against proxy/network failures.

**Tech Stack:** bash, bats-core.

## Global Constraints

Copied verbatim from the spec (`docs/superpowers/specs/2026-06-17-dotfiles-hardening-design.md` §5.4) and `CLAUDE.md`.

- macOS-only target; Linux CI is a test substrate only.
- `setup.sh`: `set -Eeuo pipefail`, sources `$DOTFILES/bin/lib/common.sh`. In functions use `return 1`, never `exit 1` (top-level `main`/flag-parse may `exit`). No `trap EXIT` in functions.
- Use the Plan 4 step runner (`step_init`/`step`/`step_summary`, `STEP_SKIP_CODE`, `STEP_DRY_RUN`) from `common.sh`. Use `log_*`/`fmt_*` helpers.
- Use the Plan 2/3 helpers (`dot_profile`, `dot_config`, `dot_docker_runtime`) from `common.sh`; persist via `dot profile set` / `dot profile set-config`.
- macOS BSD-safe; day-0 safe (guard tools with `command -v`).
- shfmt -i 2 -ci + shellcheck-clean (the gate covers `setup.sh`). Conventional Commits; no `Co-Authored-By`.
- `bin/dot test` and CI (`checks` + `pre-commit`) must stay green.

---

## Plan Roadmap (where this fits)

Plans 1–4 are merged. This is Plan 5 — the installer, consuming Plan 4's step runner. Deferred: profile-aware `dot doctor` → **Plan 6**; shell-helper audit + `sdkup` → later; config audit → final plan. A deep per-step `--dry-run` preview is out of scope (the step-level dry-run lists what would run).

**Testing note:** `setup.sh`'s install steps mutate the system and cannot be run in CI/bats. The automated coverage is the static gate (shellcheck/shfmt) plus a **`--dry-run` test** that proves setup lists every step and produces NO side effects. Re-runnability is achieved via each step's "already done → skip" guard.

---

## File Structure (Plan 5)

- `setup.sh` — **Rewrite**: flat script → `step_*` functions + flag parsing + step-runner `main` + profile selection + summary.
- `tests/setup_dryrun.bats` — **Create**: asserts `setup.sh --dry-run --non-interactive` lists steps and writes nothing.
- `bin/dot-homebrew` — **Modify** (Task 2): network-resilient `homebrew_install` curl.

---

## Task 1: Rewrite `setup.sh` as a soft-fail step-runner installer

**Files:**
- Rewrite: `setup.sh`
- Create: `tests/setup_dryrun.bats`

- [ ] **Step 1: Write the failing dry-run test**

Create `tests/setup_dryrun.bats`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/setup_dryrun.bats`
Expected: failures — the current flat `setup.sh` has no `--dry-run`/`--help`/`--profile` flags (it will try to run real steps or error).

- [ ] **Step 3: Replace `setup.sh` entirely**

Replace the whole file with:

```bash
#!/usr/bin/env bash
# Resilient dotfiles installer: every step is non-fatal and re-runnable.

set -Eeuo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"
source "$DOTFILES/bin/lib/common.sh"

DOT="$DOTFILES/bin/dot"

PROFILE_FLAG=""
NON_INTERACTIVE=0

usage() {
  cat <<EOF
  $(fmt_key "Usage:") $(fmt_cmd "setup.sh") $(fmt_value "[options]")

  Resilient dotfiles installer. Every step is independent and non-fatal: a
  blocked step is skipped, the run always completes with a summary, and
  re-running is safe.

  Options:
    --profile <personal|work>  Set the machine profile (default: prompt, else personal)
    --non-interactive          Never prompt; skip steps that need input
    -n, --dry-run              List the steps that would run, without executing them
    -h, --help                 Show this help
EOF
}

# ask_yes_no <prompt> — always false under --non-interactive.
ask_yes_no() {
  [[ "$NON_INTERACTIVE" -eq 1 ]] && return 1
  local answer
  printf "%b" "$1 [y/N] "
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

profile_file() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/profile"; }

# ── Steps: each returns 0 (ok) / STEP_SKIP_CODE (skip) / 1 (fail) ──

step_xcode() {
  if xcode-select -p &>/dev/null; then
    log_success "Xcode CLI tools already installed"
    return "$STEP_SKIP_CODE"
  fi
  log_info "Installing Xcode CLI tools..."
  xcode-select --install || return 1
  if [[ "$NON_INTERACTIVE" -eq 0 ]]; then
    log_warning "Press any key after the installation finishes"
    read -r -n 1 -s
  fi
}

step_homebrew() {
  if command -v brew &>/dev/null; then
    log_success "Homebrew already installed"
    return "$STEP_SKIP_CODE"
  fi
  "$DOT" homebrew install || return 1
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

step_profile() {
  local profile
  if [[ -n "$PROFILE_FLAG" ]]; then
    profile="$PROFILE_FLAG"
  elif [[ -f "$(profile_file)" ]]; then
    profile="$(dot_profile)"
    log_success "Profile already set: $profile"
  elif [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    profile="personal"
  else
    printf "Machine profile [1=personal (default), 2=work]: "
    local choice
    read -r choice
    case "$choice" in
      2) profile="work" ;;
      *) profile="personal" ;;
    esac
  fi
  "$DOT" profile set "$profile" || return 1
  if [[ -z "$(dot_config docker_runtime)" ]]; then
    "$DOT" profile set-config docker_runtime "$(dot_docker_runtime)" || return 1
  fi
  log_info "Profile: $profile · docker runtime: $(dot_docker_runtime)"
}

step_ssh() {
  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    log_success "SSH key already exists (~/.ssh/id_ed25519)"
    return "$STEP_SKIP_CODE"
  fi
  if ! ask_yes_no "Generate a new SSH key?"; then
    log_info "Skipping — generate later: ssh-keygen -t ed25519"
    return "$STEP_SKIP_CODE"
  fi
  local ssh_email
  printf "Email for SSH key: "
  read -r ssh_email
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$ssh_email" -f "$HOME/.ssh/id_ed25519" || return 1
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add "$HOME/.ssh/id_ed25519"
  log_info "Add this public key to GitHub → Settings → SSH Keys:"
  cat "$HOME/.ssh/id_ed25519.pub"
  if command -v pbcopy &>/dev/null; then
    pbcopy <"$HOME/.ssh/id_ed25519.pub"
    log_info "Public key copied to clipboard"
  fi
  log_warning "Press any key after adding the key to GitHub"
  read -r -n 1 -s
}

step_brew_bundle() {
  if ! command -v brew &>/dev/null; then
    log_warning "Homebrew not available — skipping bundle"
    return "$STEP_SKIP_CODE"
  fi
  "$DOT" homebrew bundle || return 1
}

step_link() {
  "$DOT" backup -v || true
  "$DOT" link all -v || return 1
}

step_shell() {
  "$DOT" shell change || return 1
}

step_git() {
  if [[ -f "$HOME/.gitconfig-local" ]]; then
    log_success "Git identity already configured (~/.gitconfig-local)"
    return "$STEP_SKIP_CODE"
  fi
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    log_info "Skipping git identity (non-interactive)"
    return "$STEP_SKIP_CODE"
  fi
  "$DOT" git setup || return 1
}

step_macos() {
  if ! ask_yes_no "Apply recommended macOS defaults?"; then
    log_info "Skipping — run 'dot macos defaults' later"
    return "$STEP_SKIP_CODE"
  fi
  "$DOT" macos defaults || return 1
}

step_sdkman() {
  if [[ -d "$HOME/.sdkman" ]]; then
    log_success "SDKMAN already installed"
    return "$STEP_SKIP_CODE"
  fi
  if ! ask_yes_no "Install SDKMAN (Java, Gradle, Maven manager)?"; then
    log_info "Skipping — install later: curl -s https://get.sdkman.io | bash"
    return "$STEP_SKIP_CODE"
  fi
  curl -fsSL --connect-timeout 10 --retry 2 https://get.sdkman.io | bash || return 1
  export SDKMAN_DIR="$HOME/.sdkman"
  # shellcheck source=/dev/null
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
  ask_yes_no "Install latest Java?" && sdk install java
  ask_yes_no "Install latest Gradle?" && sdk install gradle
  return 0
}

step_doctor() {
  # Informational — doctor's own exit code reflects post-install gaps, not a
  # setup failure, so this step never "fails".
  "$DOT" doctor || true
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        PROFILE_FLAG="${2:-}"
        shift 2
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      -n | --dry-run)
        STEP_DRY_RUN=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [[ -n "$PROFILE_FLAG" && "$PROFILE_FLAG" != "personal" && "$PROFILE_FLAG" != "work" ]]; then
    log_error "Invalid --profile: $PROFILE_FLAG (must be personal or work)"
    exit 1
  fi

  fmt_title_border "Dotfiles Setup"
  echo

  step_init
  step "Xcode Command Line Tools" step_xcode
  step "Homebrew" step_homebrew
  step "Machine profile" step_profile
  step "SSH key" step_ssh
  step "Homebrew packages" step_brew_bundle
  step "Backup & link dotfiles" step_link
  step "Default shell" step_shell
  step "Git identity" step_git
  step "macOS defaults" step_macos
  step "SDKMAN & JVM tools" step_sdkman
  step "Health check" step_doctor

  local rc=0
  step_summary || rc=1
  echo
  fmt_title_border "Setup complete"
  log_info "Open a new terminal for all changes to take effect"
  log_info "Run 'dot doctor' anytime to verify your setup"
  return "$rc"
}

main "$@"
```

- [ ] **Step 4: Run the dry-run test to verify it passes**

Run: `bats tests/setup_dryrun.bats`
Expected: `3 tests, 0 failures`.

- [ ] **Step 5: Run the full gate**

Run: `bin/dot test`
Expected: `All checks passed`. If `shfmt` flags `setup.sh`, run `shfmt -i 2 -ci -w setup.sh`. If shellcheck flags the `source "$SDKMAN_DIR/bin/sdkman-init.sh"`, the `# shellcheck source=/dev/null` directive above it handles it (keep it).

Run: `pre-commit run --all-files`
Expected: all hooks Passed/Skipped.

- [ ] **Step 6: Commit**

```bash
git add setup.sh tests/setup_dryrun.bats
git commit -m "feat(setup): rewrite installer as soft-fail step runner with profile"
```

---

## Task 2: Network/proxy resilience for the curl-piped installer

`step_sdkman` already uses `curl --connect-timeout 10 --retry 2`. Harden the Homebrew install path the same way and make it degrade gracefully behind a proxy/blocked network.

**Files:**
- Modify: `bin/dot-homebrew` (`homebrew_install`)

- [ ] **Step 1: Harden `homebrew_install`'s curl**

In `bin/dot-homebrew`, the `homebrew_install` function pipes the Homebrew installer through `bash`. Change the curl to add connect-timeout + retry and to fail loudly (not hang) behind a blocked network. Find:

```bash
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh | bash --login
```

Replace with:

```bash
  # --connect-timeout/--retry so a proxy-blocked or flaky network fails fast
  # instead of hanging; curl honors HTTPS_PROXY from the environment.
  if ! curl -fsSL --connect-timeout 10 --retry 2 \
    https://raw.githubusercontent.com/Homebrew/install/master/install.sh | bash --login; then
    log_error "Homebrew install failed (network/proxy?). Set HTTPS_PROXY or install manually: https://brew.sh"
    return 1
  fi
```

Note: `homebrew_install` is a function — if it currently uses `exit` anywhere on this path, prefer `return 1`. The `homebrew_install` success path already logs; leave it. (The `exit 0` early-return when brew is already installed may stay as-is — it is the script entry behavior for `dot homebrew install`.)

- [ ] **Step 2: Verify lint and syntax**

Run: `shellcheck -x bin/dot-homebrew && bash -n bin/dot-homebrew && shfmt -i 2 -ci -d bin/dot-homebrew && echo OK`
Expected: `OK`. If shfmt complains, run `shfmt -i 2 -ci -w bin/dot-homebrew`.

- [ ] **Step 3: Run the full gate**

Run: `bin/dot test`
Expected: `All checks passed`.

Run: `pre-commit run --all-files`
Expected: all hooks Passed/Skipped.

- [ ] **Step 4: Commit**

```bash
git add bin/dot-homebrew
git commit -m "fix(homebrew): make install curl proxy/timeout resilient"
```

---

## Done criteria for Plan 5

- `setup.sh` runs every phase as a non-fatal `step`: a blocked/declined step is skipped, the run always completes with a `N ok · M skipped · K failed` summary, and the exit code is non-zero only if a step failed.
- Re-running `setup.sh` is safe — each step detects "already done" and skips.
- `setup.sh --dry-run --non-interactive` lists every step and produces NO side effects (covered by `tests/setup_dryrun.bats`); `--profile`/`--non-interactive`/`--help` work; an invalid `--profile` exits non-zero.
- Setup chooses + persists the machine profile and `docker_runtime` via `dot profile` (the dead `HOMEBREW_DOCKER_RUNTIME` env var is gone); the brew-bundle step installs per profile.
- The Homebrew and SDKMAN curl installers use connect-timeout + retry, honor `HTTPS_PROXY`, and fail/skip gracefully rather than hang.
- `bin/dot test` and both CI jobs stay green.
