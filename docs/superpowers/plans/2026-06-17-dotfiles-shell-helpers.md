# Dotfiles Shell Helpers & Git Identity — Implementation Plan (Plan 7 of 8)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `sdkup` helper (SDKMAN upgrade-all) and wire **work/personal git identity isolation** — a `dot git work-identity` command generates a per-machine `includeIf "gitdir:<work_dir>/"` so the work identity auto-applies in work repos and the personal identity everywhere else.

**Architecture:** `sdkup` is a guarded zsh function in `home/.zsh_functions`. For identity isolation, `config/git/config` (committed, global) gains a second `[include] path = ~/.gitconfig-work-include`; `dot git work-identity` writes `~/.gitconfig-work` (the work `[user]`) and idempotently regenerates `~/.gitconfig-work-include` (the `includeIf` keyed on `work_dir` from the Plan 2 config). git resolves the conditional include per-repo. End-to-end bats proves a work repo gets the work email and a non-work repo gets the personal email.

**Tech Stack:** zsh, bash, git, bats-core.

## Global Constraints

Copied verbatim from the spec (`docs/superpowers/specs/2026-06-17-dotfiles-hardening-design.md` §5.6/§5.8) and `CLAUDE.md`.

- macOS-only target; Linux CI is a test substrate. `sdkup` is pure zsh and runs in CI; the git-identity test is cross-platform (git only).
- Git Functions rules: auto-detect main/master; check for uncommitted changes before destructive ops; all functions support `-h`/`--help`.
- `dot-*` scripts: `# Description:` on line 2; `set -Eeuo pipefail`; source `common.sh`; `return 1` not `exit 1` in functions; no `trap EXIT`. Use the Plan 2 helpers (`dot_config`, `dot_set_config`).
- Secrets isolation: work/personal identities live in separate never-committed files (`~/.gitconfig-local`, `~/.gitconfig-work`); the generated include is `~/.gitconfig-work-include` (gitignored).
- macOS BSD-safe; resolve `~` in `work_dir` to an absolute path so `includeIf gitdir:` matches.
- shfmt -i 2 -ci + shellcheck-clean (the gate covers `bin/dot-git`; `home/.zsh_functions` is zsh — covered by `zsh -n`). Conventional Commits; no `Co-Authored-By`.
- `bin/dot test` and CI must stay green.

---

## Plan Roadmap (where this fits)

Plans 1–6 are merged. This is Plan 7. The broader `home/.zsh_functions` helper audit (nav helpers missing `-h`, `zfetch`'s `return $?` bug) folds into **Plan 8** (config audit). Plan 8 also delivers the config-audit + tool-shortlist.

---

## File Structure (Plan 7)

- `home/.zsh_functions` — **Modify**: add `sdkup`.
- `tests/sdkup.bats` — **Create**: zsh-sourced tests for `sdkup`.
- `config/git/config` — **Modify**: add `[include] path = ~/.gitconfig-work-include`.
- `bin/dot-git` — **Modify**: add a `work-identity` subcommand (`git_work_identity`).
- `.gitignore` — **Modify**: ignore `.gitconfig-work*` (defense in depth; they live in `$HOME`, not the repo, but guard anyway).
- `tests/git_work_identity.bats` — **Create**: end-to-end identity-resolution test.

---

## Task 1: `sdkup` — SDKMAN upgrade-all helper

**Files:**
- Modify: `home/.zsh_functions`
- Create: `tests/sdkup.bats`

- [ ] **Step 1: Write the failing tests**

Create `tests/sdkup.bats`:

```bash
setup() { REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"; }

@test "sdkup --help exits 0 and explains itself" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -c "source '$REPO/home/.zsh_functions'; sdkup --help"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SDKMAN"* ]]
}

@test "sdkup without SDKMAN reports unavailable and returns non-zero" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -c "source '$REPO/home/.zsh_functions'; sdkup"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDKMAN"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/sdkup.bats`
Expected: failures — `sdkup` is not defined yet (`command not found: sdkup`).

- [ ] **Step 3: Add `sdkup` to `home/.zsh_functions`**

Add this function under the "Utilities" section of `home/.zsh_functions` (after `fs`):

```zsh
# Upgrade all installed SDKMAN candidates.
# Usage: sdkup [-h|--help]
sdkup() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: sdkup"
    echo "  Upgrade all installed SDKMAN candidates (runs: sdk upgrade)."
    return 0
  fi
  if ! command -v sdk >/dev/null 2>&1; then
    echo "SDKMAN not available. Open a new shell, or install: curl -s https://get.sdkman.io | bash"
    return 1
  fi
  sdk upgrade
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/sdkup.bats`
Expected: `2 tests, 0 failures` (or skipped if zsh is unavailable).

- [ ] **Step 5: Run the full gate**

Run: `bin/dot test`
Expected: `All checks passed` (the `zsh -n` syntax check covers `.zsh_functions`; the interactive smoke still opens cleanly).

- [ ] **Step 6: Commit**

```bash
git add home/.zsh_functions tests/sdkup.bats
git commit -m "feat(zsh): add sdkup to upgrade all SDKMAN candidates"
```

---

## Task 2: Work/personal git identity isolation

**Files:**
- Modify: `config/git/config`, `bin/dot-git`, `.gitignore`
- Create: `tests/git_work_identity.bats`

**Interfaces:**
- Produces: `dot git work-identity [--work-dir DIR] [--name NAME] [--email EMAIL]` — persists `work_dir` (via `dot_set_config`), writes `~/.gitconfig-work` (work `[user]`), and regenerates `~/.gitconfig-work-include` with `[includeIf "gitdir:<work_dir>/"] path = ~/.gitconfig-work`. Idempotent. Prompts for any missing value when a flag is omitted.

- [ ] **Step 1: Write the failing end-to-end test**

Create `tests/git_work_identity.bats`:

```bash
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks so includeIf gitdir matches
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export DOTFILES="$REPO"
  export TERM=dumb
  # Make git use a clean global config (the committed one) under XDG.
  export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
  mkdir -p "$XDG_CONFIG_HOME/git"
  cp "$REPO/config/git/config" "$GIT_CONFIG_GLOBAL"
  # Personal identity (applies everywhere by default).
  git config -f "$HOME/.gitconfig-local" user.email "me@home.test"
  git config -f "$HOME/.gitconfig-local" user.name "Me Personal"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "work identity applies under work_dir, personal applies elsewhere" {
  "$REPO/bin/dot-git" work-identity --work-dir "$SANDBOX/work" --name "Me Work" --email "me@work.test"

  mkdir -p "$SANDBOX/work/proj" "$SANDBOX/personal/proj"
  git -C "$SANDBOX/work/proj" init -q
  git -C "$SANDBOX/personal/proj" init -q

  run git -C "$SANDBOX/work/proj" config user.email
  [ "$output" = "me@work.test" ]
  run git -C "$SANDBOX/personal/proj" config user.email
  [ "$output" = "me@home.test" ]
}

@test "work-identity persists work_dir and is idempotent" {
  "$REPO/bin/dot-git" work-identity --work-dir "$SANDBOX/work" --name "Me Work" --email "me@work.test"
  run cat "$XDG_CONFIG_HOME/dotfiles/config"
  [[ "$output" == *"work_dir=$SANDBOX/work"* ]]
  # second run must not duplicate the includeIf
  "$REPO/bin/dot-git" work-identity --work-dir "$SANDBOX/work" --name "Me Work" --email "me@work.test"
  run bash -c "grep -c includeIf '$HOME/.gitconfig-work-include'"
  [ "$output" -eq 1 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/git_work_identity.bats`
Expected: failures — `dot-git` has no `work-identity` subcommand yet.

- [ ] **Step 3: Add the second include to `config/git/config`**

In `config/git/config`, change the `[include]` block:

```gitconfig
[include]
    # A local gitconfig, outside of version control.
    # If the file doesn't exist it is silently ignored
    path = ~/.gitconfig-local
```

to add the work-include path:

```gitconfig
[include]
    # A local gitconfig, outside of version control.
    # If the file doesn't exist it is silently ignored
    path = ~/.gitconfig-local
    # Per-machine work-identity include — generated by: dot git work-identity.
    # Holds an includeIf that applies ~/.gitconfig-work under your work_dir.
    path = ~/.gitconfig-work-include
```

- [ ] **Step 4: Add the `work-identity` subcommand to `bin/dot-git`**

In `bin/dot-git`, add this function (after `setup_git`):

```bash
git_work_identity() {
  local work_dir="" name="" email=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --work-dir)
        work_dir="${2:-}"
        shift 2
        ;;
      --name)
        name="${2:-}"
        shift 2
        ;;
      --email)
        email="${2:-}"
        shift 2
        ;;
      *)
        log_error "Unknown argument: $1"
        return 1
        ;;
    esac
  done

  if ! command -v git &>/dev/null; then
    log_error "Git is not installed."
    return 1
  fi

  fmt_title_underline "Setting up work git identity"

  [[ -z "$work_dir" ]] && work_dir="$(dot_config work_dir)"
  if [[ -z "$work_dir" ]]; then
    read -rp "Work repos directory (e.g. ~/work): " work_dir
  fi
  if [[ -z "$work_dir" ]]; then
    log_error "A work directory is required"
    return 1
  fi
  work_dir="${work_dir/#\~/$HOME}" # expand leading ~ to an absolute path
  dot_set_config work_dir "$work_dir"

  [[ -z "$name" ]] && read -rp "Work name: " name
  [[ -z "$email" ]] && read -rp "Work email: " email
  if [[ -z "$name" || -z "$email" ]]; then
    log_error "Work name and email are required"
    return 1
  fi

  git config -f "$HOME/.gitconfig-work" user.name "$name"
  git config -f "$HOME/.gitconfig-work" user.email "$email"

  # Regenerate the include (idempotent overwrite).
  {
    printf '# Generated by: dot git work-identity — do not edit.\n'
    printf '[includeIf "gitdir:%s/"]\n' "$work_dir"
    printf '\tpath = ~/.gitconfig-work\n'
  } >"$HOME/.gitconfig-work-include"

  log_success "Work identity active for repos under $work_dir"
  log_info "name: $name · email: $email"
}
```

Then wire it into `main`'s `case "$subcmd"` (add a `work-identity)` arm and document it in `usage`):

In `usage`, add under the `setup` line:

```bash
    work-identity    Configure a separate work git identity (auto-applied under work_dir)
```

In `main`'s `case "$subcmd"`, add before the `*)` arm:

```bash
    work-identity)
      git_work_identity "$@"
      ;;
```

Note: `main`'s arg loop consumes flags into `subcmd` via the `*)` arm, so `git_work_identity "$@"` would receive an already-shifted `$@`. To pass the `--work-dir/--name/--email` flags through, change `main`'s dispatch so the subcommand keeps its remaining args. Replace the `while [[ $# -gt 0 ]]` parse + dispatch in `main` with:

```bash
main() {
  if [ $# -lt 1 ]; then
    usage
    exit 0
  fi

  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    setup)
      setup_git
      ;;
    work-identity)
      shift
      git_work_identity "$@"
      ;;
    *)
      log_error "Unknown legacy command: $1"
      echo -e
      usage
      exit 1
      ;;
  esac
}
```

- [ ] **Step 5: Guard the work files in `.gitignore`**

In `.gitignore`, under the machine-local section (near `*.local` / `*-local`), add:

```gitignore
.gitconfig-work
.gitconfig-work-include
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bats tests/git_work_identity.bats`
Expected: `2 tests, 0 failures` — the work repo resolves `me@work.test`, the personal repo `me@home.test`, `work_dir` is persisted, and the include is not duplicated on re-run.

- [ ] **Step 7: Run the full gate**

Run: `shellcheck -x bin/dot-git && bash -n bin/dot-git && shfmt -i 2 -ci -d bin/dot-git && echo OK`
Expected: `OK`.

Run: `bin/dot test`
Expected: `All checks passed`.

Run: `pre-commit run --all-files`
Expected: all hooks Passed/Skipped.

- [ ] **Step 8: Commit**

```bash
git add config/git/config bin/dot-git .gitignore tests/git_work_identity.bats
git commit -m "feat(git): add work-identity isolation via work_dir conditional include"
```

---

## Done criteria for Plan 7

- `sdkup` upgrades all SDKMAN candidates, has `-h/--help`, and is guarded by `command -v sdk`; covered by bats.
- `dot git work-identity` persists `work_dir`, writes a separate `~/.gitconfig-work`, and generates an idempotent `~/.gitconfig-work-include` `includeIf`; a work repo resolves the work email and a non-work repo the personal email (end-to-end bats proof).
- `~/.gitconfig-work*` are gitignored; work and personal identities never mix and are never committed.
- `bin/dot test` and both CI jobs stay green.
