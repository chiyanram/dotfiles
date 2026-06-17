# Dotfiles Profile-Aware Doctor — Implementation Plan (Plan 6 of 8)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `dot doctor` surface the active machine profile + resolved Docker runtime, and verify the configured Docker runtime is actually installed — so work/personal drift is visible at a glance.

**Architecture:** `dot doctor` already derives its Homebrew tool checks from `dot_brewfiles` (core + active profile, from Plan 3), so it already knows which tools the profile expects. This plan adds two small functions to `bin/dot-doctor`: `check_profile` (a "Profile" section showing `profile` + `docker runtime` from the Plan 2/3 helpers) and `check_docker_runtime` (verifies the resolved runtime's cask/formula/app is present). A macOS-guarded smoke test confirms the output.

**Tech Stack:** bash, bats-core.

## Global Constraints

Copied verbatim from the spec (`docs/superpowers/specs/2026-06-17-dotfiles-hardening-design.md` §5.4) and `CLAUDE.md`.

- macOS-only target; Linux CI is a test substrate only. `dot doctor` uses macOS-only inspection (`dscl`, `/Applications`, `brew --cask`), so its smoke test is macOS-guarded (`skip` on Linux).
- `bin/dot-doctor`: `set -Eeuo pipefail`, sources `common.sh`. `return`/`exit` per the existing `dot-doctor` style (the `check_*` functions print and adjust `missing_count`/`optional_missing`; they do not `exit`).
- Use the Plan 2/3 helpers (`dot_profile`, `dot_docker_runtime`) from `common.sh`. Use `log_*`/`fmt_*`/`check_tool` patterns already in the file.
- macOS BSD-safe; avoid SC2015 (`A || B && C`) — use explicit `if`.
- shfmt -i 2 -ci + shellcheck-clean. Conventional Commits; no `Co-Authored-By`.
- `bin/dot test` and CI (`checks` + `pre-commit`) must stay green.

---

## Plan Roadmap (where this fits)

Plans 1–5 are merged. This is Plan 6 — the profile-aware doctor. Remaining after this: git conditional-includes from `work_dir` (§5.6), shell helpers + `sdkup` (§5.8), and the config-audit + tool-shortlist deliverables (§5.7).

---

## File Structure (Plan 6)

- `bin/dot-doctor` — **Modify**: add `check_profile` + `check_docker_runtime`; call them from `main`.
- `tests/dot_doctor.bats` — **Create**: a macOS-guarded smoke test asserting the Profile section renders the active profile + runtime.

---

## Task 1: Profile + Docker-runtime awareness in `dot doctor`

**Files:**
- Modify: `bin/dot-doctor`
- Create: `tests/dot_doctor.bats`

- [ ] **Step 1: Write the failing (macOS-guarded) smoke test**

Create `tests/dot_doctor.bats`:

```bash
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "doctor shows the active profile and resolved docker runtime" {
  [[ "$(uname)" == "Darwin" ]] || skip "dot doctor inspection is macOS-only"
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$REPO" TERM=dumb
  "$REPO/bin/dot-profile" set work
  # doctor exits non-zero in a sandbox (missing links/tools) — ignore that; check output.
  run "$REPO/bin/dot-doctor"
  [[ "$output" == *"Profile"* ]]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"rancher"* ]]
}

@test "doctor defaults to the personal profile and docker-desktop runtime" {
  [[ "$(uname)" == "Darwin" ]] || skip "dot doctor inspection is macOS-only"
  export HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" DOTFILES="$REPO" TERM=dumb
  run "$REPO/bin/dot-doctor"
  [[ "$output" == *"personal"* ]]
  [[ "$output" == *"docker-desktop"* ]]
}
```

- [ ] **Step 2: Run the test (it passes-as-skip on Linux; fails/empty on macOS until implemented)**

Run: `bats tests/dot_doctor.bats`
Expected on macOS: failures — the "Profile" section and the runtime name are not yet in the output. (On Linux it skips, which is a pass; implement and verify the real behavior on the macOS dev machine.)

- [ ] **Step 3: Add `check_profile` and `check_docker_runtime` to `bin/dot-doctor`**

In `bin/dot-doctor`, add these two functions alongside the other `check_*` functions (e.g. immediately after `check_java`):

```bash
check_profile() {
  local profile runtime
  profile="$(dot_profile)"
  runtime="$(dot_docker_runtime)"
  printf "  %b %b%-14s%b %b%s%b\n" "${GREEN}${SUCCESS_ICON}" "$BOLD" "profile" "$RESET" "$DIM" "$profile" "$RESET"
  printf "  %b %b%-14s%b %b%s%b\n" "${GREEN}${SUCCESS_ICON}" "$BOLD" "docker runtime" "$RESET" "$DIM" "$runtime" "$RESET"
}

check_docker_runtime() {
  local runtime installed=false
  runtime="$(dot_docker_runtime)"
  case "$runtime" in
    docker-desktop)
      if { command -v brew &>/dev/null && brew list --cask docker-desktop &>/dev/null; } || [[ -d "/Applications/Docker.app" ]]; then
        installed=true
      fi
      ;;
    rancher)
      if { command -v brew &>/dev/null && brew list --cask rancher &>/dev/null; } || [[ -d "/Applications/Rancher Desktop.app" ]]; then
        installed=true
      fi
      ;;
    colima)
      command -v colima &>/dev/null && installed=true
      ;;
  esac

  if [[ "$installed" == true ]]; then
    printf "  %b %b%-14s%b %b%s%b\n" "${GREEN}${SUCCESS_ICON}" "$BOLD" "$runtime" "$RESET" "$DIM" "installed" "$RESET"
  else
    printf "  %b %b%-14s%b %b%s%b\n" "${YELLOW}${WARNING_ICON}" "$BOLD" "$runtime" "$RESET" "$YELLOW" "not found (optional)" "$RESET"
    optional_missing=$((optional_missing + 1))
  fi
}
```

- [ ] **Step 4: Call them from `main`**

In `bin/dot-doctor` `main()`, add a Profile section right after the title block:

Find:

```bash
  fmt_title_border "Dotfiles Health Check"
  echo

  local config_issues=0
```

Replace with:

```bash
  fmt_title_border "Dotfiles Health Check"
  echo

  # Machine profile
  fmt_title_underline "Profile"
  check_profile
  echo

  local config_issues=0
```

Then, in the Homebrew section, add the runtime check after the brew-package loop. Find the closing of that block:

```bash
  else
    log_warning "No Brewfiles found under $DOTFILES/brew/"
  fi
  echo
```

Replace with:

```bash
  else
    log_warning "No Brewfiles found under $DOTFILES/brew/"
  fi
  check_docker_runtime
  echo
```

- [ ] **Step 5: Verify the smoke test (macOS) and lint**

Run: `bats tests/dot_doctor.bats`
Expected on macOS: `2 tests, 0 failures` (the Profile section shows `work`/`rancher` and `personal`/`docker-desktop`). On Linux: 2 skipped (a pass).

Run: `shellcheck -x bin/dot-doctor && bash -n bin/dot-doctor && shfmt -i 2 -ci -d bin/dot-doctor && echo OK`
Expected: `OK`. (Watch for SC2015 on the `case` branches — they use explicit `if`, so should be clean. If shfmt complains, run `shfmt -i 2 -ci -w bin/dot-doctor`.)

- [ ] **Step 6: Run the full gate + a real doctor glance**

Run: `bin/dot test`
Expected: `All checks passed`.

Run: `pre-commit run --all-files`
Expected: all hooks Passed/Skipped.

Run: `dot doctor 2>&1 | sed -n '/Profile/,/Config Links/p' | head`
Expected: the new Profile section shows your real `profile` and `docker runtime`.

- [ ] **Step 7: Commit**

```bash
git add bin/dot-doctor tests/dot_doctor.bats
git commit -m "feat(doctor): surface active profile and verify docker runtime"
```

---

## Done criteria for Plan 6

- `dot doctor` opens with a **Profile** section showing the active `profile` and resolved `docker runtime`.
- `dot doctor` verifies the configured Docker runtime (docker-desktop / rancher / colima) is installed, reporting it as installed or "not found (optional)".
- A macOS-guarded smoke test asserts the Profile output for both `work` (→ rancher) and default `personal` (→ docker-desktop); it skips cleanly on Linux CI.
- `bin/dot test` and both CI jobs stay green.
