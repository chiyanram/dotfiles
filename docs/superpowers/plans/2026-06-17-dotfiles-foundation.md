# Dotfiles Foundation — Implementation Plan (Plan 1 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the oh-my-zsh-era cruft, relocate generated shell state out of the repo, and stand up a real test harness + CI so every later plan can be built test-first.

**Architecture:** Plain bash/zsh dotfiles managed by `bin/dot`. Tests run the real `bin/dot` against a throwaway `$HOME` + a minimal fixture `DOTFILES`, using core `bats` (no external assertion libs). CI runs the same `bin/dot test` entrypoint on `ubuntu-latest` (the manager is pure bash/symlinks, so it runs on Linux); macOS-only behavior is local-only by design. A second CI job runs `pre-commit` (shellcheck + gitleaks secret scan).

**Tech Stack:** bash, zsh, bats-core, shellcheck, shfmt, gitleaks, GitHub Actions, pre-commit, just.

## Global Constraints

Copied verbatim from the design spec (`docs/superpowers/specs/2026-06-17-dotfiles-hardening-design.md`) and `CLAUDE.md`. Every task implicitly includes these.

- macOS-only target; Apple Silicon `/opt/homebrew` with Intel `/usr/local` fallback. Linux CI is a test substrate, not a supported install target.
- All bash scripts start with `set -Eeuo pipefail` and source `$DOTFILES/bin/lib/common.sh`.
- Use `log_success` / `log_error` / `log_warning` / `log_info` from `common.sh`; `printf '%b'` for ANSI color vars.
- In functions use `return 1`, never `exit 1` (kills the script under `set -e`). Never use `trap EXIT` inside a function.
- macOS ships BSD tools: no `readlink -f`, no GNU `sed -i`. Use zsh `:A`/`:h` modifiers or `cd && pwd -P`.
- Every script works on a fresh machine (day 0): guard tools with `command -v`, files with `[[ -f ]]`, dirs with `[[ -d ]]`.
- `git config <key>` returns exit 1 if missing — always `2>/dev/null || true`.
- All `dot-*` scripts have a `# Description:` comment on line 2 (auto-discovery).
- Shell indent: 2 spaces (`.editorconfig`); format with `shfmt -i 2 -ci`.
- Conventional Commits; imperative, lowercase, ≤72 chars. No `Co-Authored-By`. One logical change per commit.
- Never commit secrets, generated files, history, or `.zcompdump`.

---

## Plan Roadmap (context for this plan's place in the effort)

The spec is delivered as six sequential plans; each produces working, tested software:

1. **Foundation (this plan)** — cruft cleanup, XDG state relocation, test harness, CI, gitleaks.
2. Profile system — `~/.config/dotfiles/profile` + `config` (`work_dir`), `dot_profile`/`dot_config` helpers, `dot profile` subcommand.
3. Brewfile split — `brew/Brewfile.{core,personal,work}`; profile-aware `dot homebrew bundle`.
4. Resilient installer + `dot update all` fix + profile-aware `dot doctor`.
5. Shell helpers — `sdkup`, helper audit/repair, git conditional-include from `work_dir`.
6. Config audit + tool shortlist deliverables → approved changes.

Plans 2–6 are authored when reached (each needs the prior plan's interfaces in hand); this avoids speculative placeholders.

---

## File Structure (Plan 1)

- `.gitignore` — **Modify**: add guards for `*.local`, `*-local`, `.zcompdump*`, `*.zwc`, `**/ohmyzsh/`, history, SSH keys.
- `config/zsh/` — **Remove** (archived to `~/dotfiles-backup/` first): leftover ZDOTDIR-era debris.
- `home/.zshenv` — **Modify**: `HISTFILE` → `$XDG_STATE_HOME/zsh/history`.
- `home/.zshrc` — **Modify**: relocate `compinit` dump → `$XDG_CACHE_HOME/zsh/zcompdump`.
- `bin/dot-test` — **Create**: the `dot test` entrypoint (lint + format + syntax + smoke + bats).
- `tests/test_helper.bash` — **Create**: sandbox fixture builder.
- `tests/dot_link.bats` — **Create**: link/unlink/idempotency behavior tests.
- `.github/workflows/ci.yml` — **Create**: Linux CI running `dot test` + `pre-commit`.
- `Brewfile` — **Modify**: add `bats-core`, `shfmt`, `gitleaks`.
- `.pre-commit-config.yaml` — **Modify**: add the `gitleaks` hook.
- `justfile` — **Create**: `just test` → `bin/dot test`.

---

## Task 1: Remove oh-my-zsh-era cruft + harden `.gitignore`

Leftover ZDOTDIR-era state (`ohmyzsh/`, `.zcompdump*`, `.zsh_history`, `.zshrc.pre-oh-my-zsh`, `.DS_Store`) sits untracked in `config/zsh/`. Archive it (it may hold old history), delete it from the tree, and close the gitignore gaps so this class of file can never reappear.

**Files:**
- Remove: `config/zsh/` (archived first)
- Remove: `./.DS_Store` (on-disk, already gitignored)
- Modify: `.gitignore`

- [ ] **Step 1: Archive the cruft outside the repo (reversible safety net)**

```bash
mkdir -p ~/dotfiles-backup
mv config/zsh ~/dotfiles-backup/config-zsh-cruft-20260617
rm -f ./.DS_Store
```

- [ ] **Step 2: Verify the debris is gone from the working tree**

Run: `ls config/zsh 2>&1; git status --porcelain | grep -c 'config/zsh' || true`
Expected: `ls: config/zsh: No such file or directory` and a count of `0`.

- [ ] **Step 3: Harden `.gitignore`**

Append this block to `.gitignore` (keep the existing content above it):

```gitignore
# Generated shell state (must never live in the repo tree)
.zcompdump*
*.zwc
.zsh_history
**/ohmyzsh/
.zshrc.pre-oh-my-zsh

# Machine-local config (never committed — secrets / identity live here)
*.local
*-local

# SSH keys / certs (defense in depth)
id_rsa
id_ed25519
*.pem
*.p12
```

- [ ] **Step 4: Verify the new ignore rules match**

Run: `git check-ignore -v .zcompdump ~/.zsh_history foo.local config/x/ohmyzsh/y .zshrc.local 2>/dev/null | wc -l`
Expected: a count of `5` (every sample path is matched by a rule).

- [ ] **Step 5: Commit**

```bash
git add .gitignore
git commit -m "chore(zsh): remove oh-my-zsh-era cruft and harden gitignore"
```

---

## Task 2: Relocate shell state to XDG dirs

`HISTFILE` points at `~/.zsh_history` and `compinit` writes `~/.zcompdump` — both clutter `$HOME` and were the source of the repo-tree debris. Move them under the XDG cache/state dirs already exported in `.zshenv`, preserving existing history.

**Files:**
- Modify: `home/.zshenv:10`
- Modify: `home/.zshrc:32-37`

- [ ] **Step 1: Point `HISTFILE` at XDG state in `home/.zshenv`**

Replace the current history block:

```zsh
HISTFILE="$HOME/.zsh_history"
HISTSIZE=1000000
SAVEHIST=1000000
```

with:

```zsh
# History lives in XDG state, never $HOME root or the repo tree
export HISTFILE="$XDG_STATE_HOME/zsh/history"
[[ -d "${HISTFILE:h}" ]] || mkdir -p "${HISTFILE:h}"
HISTSIZE=1000000
SAVEHIST=1000000
```

- [ ] **Step 2: Relocate the `compinit` dump in `home/.zshrc`**

Replace the compinit block (lines 32–37):

```zsh
autoload -U compinit add-zsh-hook
if [[ -n "$HOME"/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi
```

with:

```zsh
autoload -U compinit add-zsh-hook
ZCOMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
[[ -d "${ZCOMPDUMP:h}" ]] || mkdir -p "${ZCOMPDUMP:h}"
# Rebuild fully if the dump is stale (>24h), otherwise use the cache (-C)
if [[ -n $ZCOMPDUMP(#qN.mh+24) ]]; then
    compinit -d "$ZCOMPDUMP"
else
    compinit -C -d "$ZCOMPDUMP"
fi
```

- [ ] **Step 3: Migrate existing history (one-time, preserves your shell history)**

Run:

```bash
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
[[ -f ~/.zsh_history && ! -f "${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history" ]] \
  && mv ~/.zsh_history "${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history" || true
```

- [ ] **Step 4: Re-link and verify state lands in XDG, not `$HOME` (local macOS check)**

Run:

```bash
dot link all -f
rm -f ~/.zcompdump
zsh -i -c 'echo ok'
[[ ! -f ~/.zcompdump ]] && [[ ! -f ~/.zsh_history ]] \
  && [[ -f "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump" ]] \
  && echo "STATE_RELOCATED_OK"
```

Expected: prints `ok` then `STATE_RELOCATED_OK`. (CI skips this — it needs a configured machine.)

- [ ] **Step 5: Commit**

```bash
git add home/.zshenv home/.zshrc
git commit -m "refactor(zsh): relocate history and compdump to XDG dirs"
```

---

## Task 3: bats sandbox harness for `dot link`

Stand up `bats` tests that drive the real `bin/dot` against a throwaway `$HOME` and a minimal fixture `DOTFILES`. This is the harness every later plan builds on, and it proves link/unlink correctness and idempotency (the "half-configured state" fix).

**Files:**
- Create: `tests/test_helper.bash`
- Create: `tests/dot_link.bats`
- Modify: `Brewfile` (add `bats-core`)

**Interfaces:**
- Produces: `setup_sandbox()` / `teardown_sandbox()` (in `tests/test_helper.bash`). After `setup_sandbox`, these env vars are exported for the test: `SANDBOX` (temp root), `HOME` (`$SANDBOX/home`), `XDG_CONFIG_HOME` (`$HOME/.config`), `DOTFILES` (`$SANDBOX/dotfiles`, a minimal fixture containing `bin/dot`, `bin/lib/common.sh`, `config/demo/demo.conf`, `home/.demorc`), and `DOT` (`$DOTFILES/bin/dot`). Later plans `load test_helper` and reuse these.

- [ ] **Step 1: Add the bats runner to the Brewfile**

In `Brewfile`, under the `# Development tools` section (after the `brew 'shellcheck'` line), add:

```ruby
brew 'bats-core'                       # bash automated testing system (test harness)
brew 'shfmt'                           # shell script formatter (lint gate)
brew 'gitleaks'                        # secret scanner (pre-commit + CI)
```

Then install locally so the tests can run:

Run: `brew install bats-core shfmt gitleaks`
Expected: all three install (or report "already installed").

- [ ] **Step 2: Write the sandbox helper**

Create `tests/test_helper.bash`:

```bash
#!/usr/bin/env bash
# Shared helpers for dot-manager sandbox tests (core bats only — no external libs).

# Build an isolated sandbox: a fake HOME plus a minimal fixture DOTFILES that
# carries the real dot + common.sh so the manager runs exactly as in production.
setup_sandbox() {
  local repo_root
  repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"

  SANDBOX="$(mktemp -d)"
  export SANDBOX
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export DOTFILES="$SANDBOX/dotfiles"
  export DOT="$DOTFILES/bin/dot"
  export TERM=dumb # no tty in CI; keeps tput/colors quiet

  mkdir -p "$HOME" "$XDG_CONFIG_HOME" \
    "$DOTFILES/bin/lib" "$DOTFILES/config/demo" "$DOTFILES/home"

  cp "$repo_root/bin/dot" "$DOTFILES/bin/dot"
  cp "$repo_root/bin/lib/common.sh" "$DOTFILES/bin/lib/common.sh"
  printf 'demo config\n' >"$DOTFILES/config/demo/demo.conf"
  printf 'demo home rc\n' >"$DOTFILES/home/.demorc"
}

teardown_sandbox() {
  [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"
}
```

- [ ] **Step 3: Write the failing behavior tests**

Create `tests/dot_link.bats`:

```bash
load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "link all symlinks a config package into XDG_CONFIG_HOME" {
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ]
  [ "$(readlink "$XDG_CONFIG_HOME/demo")" = "$DOTFILES/config/demo" ]
}

@test "link all symlinks a home file into HOME" {
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ -L "$HOME/.demorc" ]
  [ "$(readlink "$HOME/.demorc")" = "$DOTFILES/home/.demorc" ]
}

@test "link all is idempotent (second run is a clean no-op)" {
  run "$DOT" link all
  [ "$status" -eq 0 ]
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ]
  [ "$(readlink "$XDG_CONFIG_HOME/demo")" = "$DOTFILES/config/demo" ]
  [ -L "$HOME/.demorc" ]
}

@test "unlink all removes the symlinks it created" {
  "$DOT" link all
  run "$DOT" unlink all
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/demo" ]
  [ ! -e "$HOME/.demorc" ]
}
```

- [ ] **Step 4: Run the tests to verify they fail before the harness is wired**

Run: `bats tests/ 2>&1 | tail -5`
Expected (before `bats-core` is on PATH): `bats: command not found`. After Step 1's install, re-run and expect all 4 tests to **pass** — they exercise the already-working manager, so green here confirms the harness itself works.

Run: `bats tests/`
Expected: `4 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_helper.bash tests/dot_link.bats Brewfile
git commit -m "test: add bats sandbox harness for dot link/unlink idempotency"
```

---

## Task 4: `dot test` entrypoint + lint/format gates

Add a single `dot test` command that runs every static and behavioral check, so "green locally" equals "green in CI." Normalize existing shell formatting first so the `shfmt` gate starts green.

**Files:**
- Create: `bin/dot-test`
- Create: `justfile`
- Modify (one-time normalization): `bin/dot`, `bin/lib/common.sh`, `setup.sh`, `bootstrap.sh`

- [ ] **Step 1: Normalize existing shell formatting (so the gate is green from day one)**

Run:

```bash
shfmt -i 2 -ci -w bin/dot bin/lib/common.sh setup.sh bootstrap.sh
git diff --stat
```

Expected: a small formatting-only diff. Review it contains no logic changes.

- [ ] **Step 2: Commit the normalization separately**

```bash
git add bin/dot bin/lib/common.sh setup.sh bootstrap.sh
git commit -m "style(shell): normalize formatting with shfmt"
```

- [ ] **Step 3: Create the `dot test` entrypoint**

Create `bin/dot-test` (chmod +x in Step 4):

```bash
#!/usr/bin/env bash
# Description: Run all dotfiles checks — lint, format, syntax, smoke, and bats tests
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
DOTFILES="${DOTFILES:-$(cd "$script_dir/.." && pwd -P)}"
source "$DOTFILES/bin/lib/common.sh"

failed=0

run_check() {
  local name="$1"
  shift
  if "$@"; then
    log_success "$name"
  else
    log_error "$name failed"
    failed=1
  fi
}

bash_scripts() {
  printf '%s\n' \
    "$DOTFILES/bin/dot" \
    "$DOTFILES/bin/dot-test" \
    "$DOTFILES/bin/lib/common.sh" \
    "$DOTFILES/setup.sh" \
    "$DOTFILES/bootstrap.sh"
}

check_shellcheck() {
  command -v shellcheck >/dev/null || {
    log_warning "shellcheck not installed, skipping"
    return 0
  }
  bash_scripts | xargs shellcheck -x
}

check_shfmt() {
  command -v shfmt >/dev/null || {
    log_warning "shfmt not installed, skipping"
    return 0
  }
  bash_scripts | xargs shfmt -i 2 -ci -d
}

check_zsh_syntax() {
  command -v zsh >/dev/null || {
    log_warning "zsh not installed, skipping"
    return 0
  }
  local f
  for f in "$DOTFILES"/home/.zshenv "$DOTFILES"/home/.zshrc \
    "$DOTFILES"/home/.zsh_functions "$DOTFILES"/home/.zsh_aliases \
    "$DOTFILES"/home/.docker_aliases "$DOTFILES"/home/.zprofile; do
    [[ -f "$f" ]] || continue
    zsh -n "$f" || return 1
  done
}

check_zsh_smoke() {
  [[ -n "${CI:-}" ]] && {
    log_info "CI: skipping interactive zsh smoke (local-only)"
    return 0
  }
  command -v zsh >/dev/null || {
    log_warning "zsh not installed, skipping"
    return 0
  }
  zsh -i -c 'echo ok' >/dev/null
}

check_bats() {
  command -v bats >/dev/null || {
    log_warning "bats not installed, skipping"
    return 0
  }
  bats "$DOTFILES/tests"
}

main() {
  fmt_title_underline "Running dotfiles checks"
  run_check "shellcheck" check_shellcheck
  run_check "shfmt" check_shfmt
  run_check "zsh syntax" check_zsh_syntax
  run_check "zsh smoke" check_zsh_smoke
  run_check "bats tests" check_bats
  echo
  if [[ "$failed" -eq 0 ]]; then
    log_success "All checks passed"
  else
    log_error "Some checks failed"
    return 1
  fi
}

main "$@"
```

- [ ] **Step 4: Make it executable and add the `just` alias**

Run: `chmod +x bin/dot-test`

Create `justfile`:

```just
# Project task runner. Run `just` to list recipes.

# Run all dotfiles checks (lint, format, syntax, smoke, bats)
test:
    bin/dot test
```

- [ ] **Step 5: Run the full suite and verify it passes**

Run: `bin/dot test`
Expected: `shellcheck`, `shfmt`, `zsh syntax`, `zsh smoke`, `bats tests` each report success, then `All checks passed`.

Run: `CI=true bin/dot test`
Expected: same, but `zsh smoke` reports "CI: skipping interactive zsh smoke (local-only)".

- [ ] **Step 6: Commit**

```bash
git add bin/dot-test justfile
git commit -m "build: add dot test entrypoint with shellcheck/shfmt/bats gates"
```

---

## Task 5: GitHub Actions CI on Linux

Run `dot test` on every push and PR. The manager is pure bash/symlinks, so the sandbox + lint + syntax + bats checks all run on `ubuntu-latest`; the interactive smoke is skipped via `CI=true`.

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  checks:
    name: Lint & tests
    runs-on: ubuntu-latest
    env:
      CI: "true"
    steps:
      - uses: actions/checkout@v4
      - name: Install tools
        run: |
          sudo apt-get update
          sudo apt-get install -y zsh bats shellcheck
          SHFMT_VERSION=v3.10.0
          sudo curl -fsSL -o /usr/local/bin/shfmt \
            "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_amd64"
          sudo chmod +x /usr/local/bin/shfmt
      - name: Run dot test
        run: ./bin/dot-test
```

- [ ] **Step 2: Verify the workflow parses and the runner command is correct locally**

Run: `CI=true ./bin/dot-test && echo WORKFLOW_CMD_OK`
Expected: checks pass, prints `WORKFLOW_CMD_OK` (this is exactly what the `Run dot test` step executes).

- [ ] **Step 3: Commit and push to confirm green CI**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run dot test on linux for push and pull requests"
git push -u origin feat/dotfiles-hardening
```

Expected: the `checks` job goes green on the branch. Verify with `gh run list --branch feat/dotfiles-hardening --limit 1`.

---

## Task 6: gitleaks secret scanning (pre-commit + CI)

Secret isolation is a hard requirement (work tokens/keys must never be committed). Add `gitleaks` to pre-commit and run all hooks in CI.

**Files:**
- Modify: `.pre-commit-config.yaml`
- Modify: `.github/workflows/ci.yml` (add a `pre-commit` job)

- [ ] **Step 1: Add the gitleaks hook**

In `.pre-commit-config.yaml`, add this repo block after the existing `shellcheck-py` block (before the `default_install_hook_types` line):

```yaml
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks
```

- [ ] **Step 2: Verify the hook runs clean on the repo**

Run: `pre-commit run gitleaks --all-files`
Expected: `gitleaks....Passed` (no secrets detected). If it fails, a real secret is tracked — stop and remediate before continuing.

- [ ] **Step 3: Add the pre-commit CI job**

Append this job to `.github/workflows/ci.yml` (under `jobs:`, as a sibling of `checks`):

```yaml
  pre-commit:
    name: pre-commit hooks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Run pre-commit
        run: |
          pip install pre-commit
          pre-commit run --all-files --show-diff-on-failure
```

- [ ] **Step 4: Verify the full hook set passes locally (mirrors the CI job)**

Run: `pre-commit run --all-files`
Expected: every hook reports `Passed` (or `Skipped` when no matching files).

- [ ] **Step 5: Commit and confirm both CI jobs are green**

```bash
git add .pre-commit-config.yaml .github/workflows/ci.yml Brewfile
git commit -m "ci(security): add gitleaks secret scanning to pre-commit and CI"
git push
```

Expected: both `checks` and `pre-commit` jobs go green. Verify with `gh run list --branch feat/dotfiles-hardening --limit 1`.

> Note: `Brewfile` already gained `gitleaks` in Task 3 Step 1; it is re-listed in this commit only if it was not staged earlier. If `git status` shows it clean, drop it from the `git add`.

---

## Done criteria for Plan 1

- `config/zsh/` debris is gone; `.gitignore` blocks its return; `git check-ignore` confirms the new rules.
- New terminals write history to `$XDG_STATE_HOME/zsh/history` and the compdump to `$XDG_CACHE_HOME/zsh/zcompdump`; nothing lands in `$HOME` root or the repo.
- `bin/dot test` runs shellcheck + shfmt + `zsh -n` + interactive smoke + 4 bats tests, all green.
- GitHub Actions `checks` and `pre-commit` jobs are green on `feat/dotfiles-hardening`.
- gitleaks runs in pre-commit and CI; no secret is tracked.
