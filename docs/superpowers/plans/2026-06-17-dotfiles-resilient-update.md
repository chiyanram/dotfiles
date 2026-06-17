# Dotfiles Resilient Update — Implementation Plan (Plan 4 of 8)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable soft-fail step runner, fix the `trap EXIT`/cursor bugs in the spinner and `cmd_backup`, and rewrite `dot update` so one failing updater never aborts the rest — it records the failure and prints an end-of-run summary.

**Architecture:** A small step-runner API in `common.sh` (`step_init` / `step` / `step_summary`, with a skip sentinel and a dry-run mode) runs named steps non-fatally and tallies ok/skip/fail. `dot update` routes every updater through it (single or `all`), so the run always completes and exits non-zero only if a step truly failed. The spinner and `cmd_backup` are fixed to never leave the terminal corrupted and to obey the "no `trap EXIT` in functions" rule. Plans 5 (installer) and 6 (doctor) reuse the same step runner.

**Tech Stack:** bash, bats-core.

## Global Constraints

Copied verbatim from the spec (`docs/superpowers/specs/2026-06-17-dotfiles-hardening-design.md` §5.4/§5.4a) and `CLAUDE.md`.

- macOS-only target; Linux CI is a test substrate only.
- All bash scripts: `set -Eeuo pipefail`, source `$DOTFILES/bin/lib/common.sh`.
- In functions use `return 1`, never `exit 1`. **Never use `trap EXIT` inside a function** — use explicit cleanup. (This plan fixes two existing violations.)
- macOS BSD tools: no `readlink -f`, no GNU `sed -i`. `tput` cursor ops only when stdout is a tty.
- Day-0 safe: guard tools with `command -v`, files with `[[ -f ]]`.
- `dot-*` scripts: `# Description:` on line 2; `log_*`/`fmt_*` helpers; shfmt -i 2 -ci; shellcheck-clean (the gate covers `bin/dot`, every `bin/dot-*`, `bin/lib/*.sh`, `setup.sh`, `bootstrap.sh`).
- Arrays used under `set -u` must use the `"${arr[@]+"${arr[@]}"}"` empty-guard idiom.
- Conventional Commits; imperative, lowercase, ≤72 chars. No `Co-Authored-By`.
- `bin/dot test` and CI (`checks` + `pre-commit`) must stay green.

---

## Plan Roadmap (where this fits)

Plans 1–3 are merged. This is Plan 4. It delivers the soft-fail step runner + `dot update` fix + the spinner/trap fixes. Deferred (reuse this plan's step runner):
- Resilient `setup.sh` installer (soft-fail steps, profile selection, proxy hardening) → **Plan 5**.
- Profile-aware `dot doctor` → **Plan 6**.
- `sdkup` + shell-helper audit → later plan (spec §5.8).
- A deep per-updater `--dry-run` preview (this plan ships a step-level dry-run that lists what would run).

---

## File Structure (Plan 4)

- `bin/lib/common.sh` — **Modify**: add the step-runner API (`step_init`, `step`, `step_summary`, `STEP_SKIP_CODE`, dry-run flag); fix `spinner` / `run_with_spinner` (tty-guard `tput`, remove the in-function `trap EXIT`).
- `bin/dot` — **Modify**: fix `cmd_backup`'s in-function `trap EXIT` (explicit cleanup; `return 1` not `exit 1`).
- `bin/dot-update` — **Modify**: route every updater through the step runner; updaters `return $STEP_SKIP_CODE` on skip; `--dry-run`; exit non-zero only on a real failure.
- `tests/step_runner.bats` — **Create**: unit tests for the step runner.
- `tests/dot_backup.bats` — **Create**: behavior test for `dot backup` (archive created, temp file cleaned).

---

## Task 1: Soft-fail step runner + spinner/cursor fixes in `common.sh`

Add the reusable step runner (test-first) and fix the spinner's `trap EXIT` + non-tty cursor artifacts.

**Files:**
- Create: `tests/step_runner.bats`
- Modify: `bin/lib/common.sh`

**Interfaces:**
- Produces (from `common.sh`):
  - `STEP_SKIP_CODE` (=78) — a step command returns this to signal "skipped".
  - `step_init` — reset the tally; honors `STEP_DRY_RUN` (when set to `1`, steps are listed, not executed).
  - `step <label> <command> [args...]` — run the command non-fatally; record ok (exit 0) / skip (exit `STEP_SKIP_CODE`) / fail (other). Always returns 0.
  - `step_summary` — print the `N ok · M skipped · K failed` tally with skipped/failed labels; return 1 iff any step failed.

- [ ] **Step 1: Write the failing step-runner tests**

Create `tests/step_runner.bats`:

```bash
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  source "$REPO/bin/lib/common.sh"
}

@test "step records ok and summary returns 0 when nothing failed" {
  step_init
  step "a" true
  run step_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 ok"* ]]
}

@test "step records skip via STEP_SKIP_CODE" {
  step_init
  step "b" bash -c "exit $STEP_SKIP_CODE"
  run step_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 skipped"* ]]
  [[ "$output" == *"b"* ]]
}

@test "step records failure and summary returns non-zero" {
  step_init
  step "c" false
  run step_summary
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 failed"* ]]
  [[ "$output" == *"c"* ]]
}

@test "a failing step does not abort subsequent steps" {
  step_init
  step "x" false
  step "y" true
  [ "$_step_ok" -eq 1 ]
  [ "${#_step_failed[@]}" -eq 1 ]
}

@test "mixed run tallies all three categories" {
  step_init
  step "ok1" true
  step "ok2" true
  step "skip1" bash -c "exit $STEP_SKIP_CODE"
  step "fail1" false
  run step_summary
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 ok"* ]]
  [[ "$output" == *"1 skipped"* ]]
  [[ "$output" == *"1 failed"* ]]
}

@test "dry-run lists steps without executing them" {
  step_init
  export STEP_DRY_RUN=1
  step_init
  local marker="$BATS_TEST_TMPDIR/ran"
  step "should-not-run" touch "$marker"
  [ ! -f "$marker" ]
  run step_summary
  [ "$status" -eq 0 ]
  unset STEP_DRY_RUN
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/step_runner.bats`
Expected: failures — `step_init`/`step`/`step_summary` are not defined yet.

- [ ] **Step 3: Add the step runner to `common.sh`**

In `bin/lib/common.sh`, add this section immediately before the final `setup_colors` line:

```bash
########################################################
# Soft-fail step runner
########################################################
# Run named steps non-fatally and tally the outcomes. A step command returns
# 0 (ok), STEP_SKIP_CODE (skipped), or anything else (failed). The runner never
# propagates a failure, so one bad step never aborts the rest.

STEP_SKIP_CODE=78

step_init() {
  _step_ok=0
  _step_skipped=()
  _step_failed=()
}

# step <label> <command> [args...]
step() {
  local label="$1"
  shift
  if [[ "${STEP_DRY_RUN:-0}" == "1" ]]; then
    log_info "would run: $label"
    _step_ok=$((_step_ok + 1))
    return 0
  fi
  local rc=0
  "$@" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    _step_ok=$((_step_ok + 1))
  elif [[ "$rc" -eq "$STEP_SKIP_CODE" ]]; then
    _step_skipped+=("$label")
  else
    _step_failed+=("$label")
  fi
  return 0
}

# step_summary — print the tally; return 1 if any step failed.
step_summary() {
  echo
  fmt_title_underline "Summary"
  printf "  %b%d ok%b  %b%d skipped%b  %b%d failed%b\n" \
    "$GREEN" "$_step_ok" "$RESET" \
    "$YELLOW" "${#_step_skipped[@]}" "$RESET" \
    "$RED" "${#_step_failed[@]}" "$RESET"
  local s
  for s in "${_step_skipped[@]+"${_step_skipped[@]}"}"; do
    printf "    %b⊘ %s%b\n" "$YELLOW" "$s" "$RESET"
  done
  for s in "${_step_failed[@]+"${_step_failed[@]}"}"; do
    printf "    %b✗ %s%b\n" "$RED" "$s" "$RESET"
  done
  [[ "${#_step_failed[@]}" -eq 0 ]]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/step_runner.bats`
Expected: `6 tests, 0 failures`.

- [ ] **Step 5: Fix the spinner's `trap EXIT` and non-tty cursor artifacts**

In `bin/lib/common.sh`, in the `spinner()` function:

(a) Replace the cursor-hide line `tput civis` with a tty-guarded version:

```bash
  [[ -t 1 ]] && tput civis
```

(b) In the inner `_spinner_cleanup` function, tty-guard its `tput` calls:

```bash
  _spinner_cleanup() {
    [[ -t 1 ]] && tput cnorm # Restore cursor
    [[ -t 1 ]] && tput el    # Clear line
    echo -en "\r${RESET}"
  }
```

(c) Remove the line `trap _spinner_cleanup EXIT SIGINT SIGTERM` entirely (it violates the no-`trap EXIT`-in-functions rule). The explicit `_spinner_cleanup` call already present at the end of `spinner()` handles cleanup on the normal path.

In `run_with_spinner()`, after the `wait $!` / exit-status capture and the `echo -en "\r\033[K"` line, add a belt-and-suspenders cursor restore:

```bash
  [[ -t 1 ]] && tput cnorm
```

- [ ] **Step 6: Run the full gate**

Run: `bats tests/step_runner.bats`
Expected: `6 tests, 0 failures`.

Run: `bin/dot test`
Expected: `All checks passed`. If `shfmt` flags `common.sh`, run `shfmt -i 2 -ci -w bin/lib/common.sh`.

- [ ] **Step 7: Commit**

```bash
git add bin/lib/common.sh tests/step_runner.bats
git commit -m "feat(lib): add soft-fail step runner and fix spinner trap/cursor"
```

---

## Task 2: Fix `cmd_backup`'s in-function `trap EXIT`

`cmd_backup` in `bin/dot` sets `trap 'rm -f "$tmpfile"' EXIT` inside the function — it overwrites the top-level `trap cleanup ... EXIT`, so after a backup the global cursor-restore no longer fires. Replace it with explicit cleanup and convert its `exit 1` calls to `return 1`.

**Files:**
- Modify: `bin/dot` (`cmd_backup`)
- Create: `tests/dot_backup.bats`

- [ ] **Step 1: Write the failing backup test**

Create `tests/dot_backup.bats`:

```bash
load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "backup creates an archive of a real (non-symlink) config file" {
  # Place a real file where a home dotfile would be linked
  printf 'real contents\n' >"$HOME/.demorc"
  run "$DOT" backup -d "$SANDBOX/bk"
  [ "$status" -eq 0 ]
  # exactly one archive was produced
  run bash -c "ls \"$SANDBOX/bk\"/dotfiles_backup_*.tar.gz | wc -l"
  [ "$output" -eq 1 ]
}

@test "backup leaves no temp files behind (isolated TMPDIR)" {
  printf 'real contents\n' >"$HOME/.demorc"
  export TMPDIR="$SANDBOX/tmp"
  mkdir -p "$TMPDIR"
  "$DOT" backup -d "$SANDBOX/bk" >/dev/null 2>&1
  # cmd_backup's mktemp lands in TMPDIR; after the run it must be empty again.
  run bash -c "ls -A \"$TMPDIR\" | wc -l"
  [ "$output" -eq 0 ]
}

@test "backup with no real files to back up still exits 0" {
  run "$DOT" backup -d "$SANDBOX/bk"
  [ "$status" -eq 0 ]
}
```

(The `test_helper` `setup_sandbox` already builds a fixture `DOTFILES` with `home/.demorc`; placing a real `$HOME/.demorc` makes `cmd_backup` find a non-symlink file to archive.)

- [ ] **Step 2: Run the test to verify the relevant behavior (and that it currently passes for archive creation)**

Run: `bats tests/dot_backup.bats`
Expected: the archive-creation and exit-0 tests pass against the current code; the temp-file test documents the desired post-fix behavior. If all three already pass, that is fine — the fix below is about the `trap EXIT` correctness, which the temp-file test guards.

- [ ] **Step 3: Replace the `trap EXIT` with explicit cleanup**

In `bin/dot` `cmd_backup`, find:

```bash
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT
```

Replace with just:

```bash
  tmpfile=$(mktemp)
```

Then ensure the temp file is removed on every exit path. In the archive block, change:

```bash
    tar -czf "${backup_path}.tar.gz" -C "$HOME" -T "$tmpfile" || {
      log_error "Failed to create backup archive"
      exit 1
    }
```

to:

```bash
    if ! tar -czf "${backup_path}.tar.gz" -C "$HOME" -T "$tmpfile"; then
      log_error "Failed to create backup archive"
      rm -f "$tmpfile"
      return 1
    fi
```

And at the very end of `cmd_backup` (after the success/`No files to backup` branch, before the function closes), add:

```bash
  rm -f "$tmpfile"
```

Also convert the two earlier `exit 1` calls in `cmd_backup`'s argument parser (the `-d` missing-directory case and the unknown-argument case) to `return 1` (they are inside the function). Leave the rest of `cmd_backup` unchanged.

- [ ] **Step 4: Verify the fix and that the global trap survives a backup**

Run: `bats tests/dot_backup.bats`
Expected: all 3 tests pass.

Run: `shellcheck -x bin/dot && bash -n bin/dot && shfmt -i 2 -ci -d bin/dot && echo OK`
Expected: `OK`.

- [ ] **Step 5: Run the full gate**

Run: `bin/dot test`
Expected: `All checks passed` (the existing `dot_link` tests plus the new `dot_backup` tests).

- [ ] **Step 6: Commit**

```bash
git add bin/dot tests/dot_backup.bats
git commit -m "fix(dot): replace cmd_backup trap EXIT with explicit cleanup"
```

---

## Task 3: Route `dot update` through the step runner

Make `dot update` (single or `all`) soft-fail: each updater runs as a step, the run always completes, a summary prints, and the exit code is non-zero only if a real failure occurred. Updaters signal "skip" with `STEP_SKIP_CODE`. Add `--dry-run`.

**Files:**
- Modify: `bin/dot-update`

- [ ] **Step 1: Make the updaters signal skip with `STEP_SKIP_CODE`**

In `bin/dot-update`, change every "skip" path from `return 0` to `return "$STEP_SKIP_CODE"`. These are the guard clauses that currently `log_warning ... ; return 0`:
- `update_homebrew`: the `Homebrew is not installed` guard.
- `update_nvim_plugins`: the `Neovim is not installed` guard.
- `update_dotfiles`: the `Not on main branch` guard AND the `Dotfiles are up to date` early return.
- `update_zsh_plugins`: the `No ZSH plugins directory found` guard AND the `No ZSH plugins installed yet` guard.
- `update_sdkman`: the `SDKMAN is not installed` guard.

Leave the actual-work `return 0` / `return 1` (success / error) paths unchanged. (Example: in `update_homebrew`, the `log_warning "Homebrew is not installed. Skipping..."` line's following `return 0` becomes `return "$STEP_SKIP_CODE"`.)

- [ ] **Step 2: Rewrite `main` to use the step runner**

Replace the `main()` function in `bin/dot-update` with:

```bash
main() {
  local subcmd=""
  local verbose=false
  export STEP_DRY_RUN=0

  if [ $# -lt 1 ]; then
    usage
    exit 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      -v | --verbose)
        verbose=true
        shift
        ;;
      -n | --dry-run)
        STEP_DRY_RUN=1
        shift
        ;;
      *)
        subcmd="$1"
        shift
        ;;
    esac
  done

  step_init

  case "$subcmd" in
    nvim | vim) step "Neovim plugins" update_nvim_plugins ;;
    homebrew | brew) step "Homebrew" update_homebrew ;;
    dotfiles) step "dotfiles" update_dotfiles ;;
    zsh) step "ZSH plugins" update_zsh_plugins ;;
    sdkman) step "SDKMAN" update_sdkman ;;
    all)
      step "Neovim plugins" update_nvim_plugins
      step "Homebrew" update_homebrew
      step "ZSH plugins" update_zsh_plugins
      step "SDKMAN" update_sdkman
      step "dotfiles" update_dotfiles
      ;;
    *)
      log_error "Unknown $command_name command: $subcmd"
      echo -e
      usage
      exit 1
      ;;
  esac

  step_summary
}

main "$@"
```

Note: `main "$@"` is the script entry, so `step_summary`'s non-zero return (a real failure occurred) becomes the script's exit code under `set -e` — exactly the desired behavior (the run completed, but signals failure). The `$verbose` variable is still read by the updaters via the enclosing scope.

- [ ] **Step 3: Verify lint and a dry-run**

Run: `shellcheck -x bin/dot-update && bash -n bin/dot-update && shfmt -i 2 -ci -d bin/dot-update && echo OK`
Expected: `OK`. (If `shellcheck` flags `verbose` as unused in `main`, confirm the updaters still reference it; it is read in their scope. If shfmt complains, run `shfmt -i 2 -ci -w bin/dot-update`.)

Run: `DOTFILES="$PWD" ./bin/dot-update all --dry-run`
Expected: prints `would run: Neovim plugins` … `would run: dotfiles` and a `5 ok` summary, WITHOUT running any updater.

- [ ] **Step 4: Verify a real single update completes with a summary**

Run: `DOTFILES="$PWD" ./bin/dot-update dotfiles`
Expected: runs the dotfiles updater (up-to-date or pulls), then prints a `Summary` line. Exit 0 on success/skip. (This touches the real repo network — if offline, it will report a failed/skipped step in the summary without crashing, which is the point.)

- [ ] **Step 5: Run the full gate**

Run: `bin/dot test`
Expected: `All checks passed`.

Run: `pre-commit run --all-files`
Expected: all hooks Passed/Skipped.

- [ ] **Step 6: Commit**

```bash
git add bin/dot-update
git commit -m "fix(update): make dot update soft-fail with an end-of-run summary"
```

---

## Done criteria for Plan 4

- `step_init` / `step` / `step_summary` exist in `common.sh`, are unit-covered (6 tests), and never abort on a failing step.
- The spinner no longer sets a `trap EXIT` and only touches the cursor when stdout is a tty (no `[?12l[?25h` artifacts in captured output).
- `cmd_backup` no longer overwrites the global `EXIT` trap; it cleans its temp file explicitly and uses `return 1`. `dot backup` is behavior-tested (archive created, no temp-file leak).
- `dot update all` **always completes** — a failing updater is recorded, the rest still run, and a summary prints; the command exits non-zero only when a step actually failed. `--dry-run` lists what would run.
- `bin/dot test` and both CI jobs stay green.
