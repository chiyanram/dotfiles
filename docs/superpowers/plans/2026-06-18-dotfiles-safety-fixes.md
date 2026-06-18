# Dotfiles Safety Fixes (Audit P1) — Implementation Plan (Plan 9)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Land the high-severity safety/correctness fixes from the config audit (`docs/audit/config-audit.md` P1): stop POSIX-command shadowing, fix `zfetch` error-swallowing, guard the Intel/gnubin PATH entries, fix the aerospace service-mode trap, defang the destructive git `cleanup` alias, stop `dot link` from linking empty config dirs (the `config/docker/` clobber risk), and harden CI (SHA-pin actions + concurrency + timeouts).

**Tech Stack:** zsh, bash, git, GitHub Actions, bats.

## Global Constraints
- macOS-only; Linux CI substrate. `set -Eeuo pipefail`; `return 1` not `exit 1` in functions; no `trap EXIT` in functions; BSD-safe.
- Never alias POSIX core commands (`grep`, `du`, `ps`, `cat`, `find`, `sed`, `awk`, `sort`) — aliases are baked into functions defined later (e.g. SDKMAN), so they break tools.
- `dot-*`: `# Description:` line 2; `log_*`/`fmt_*`; shfmt -i 2 -ci + shellcheck-clean. After zsh changes, `zsh -n` + `zsh -i -c 'echo ok'` must pass.
- Conventional Commits; no `Co-Authored-By`. `bin/dot test` + CI stay green.

---

## File Structure
- `home/.zsh_aliases` — **Modify**: remove POSIX-shadowing aliases, add non-shadowing `catt`/`duu`/`pss`.
- `home/.zshrc` — **Modify**: `[[ -d ]]`-guard the gnubin + Intel `/usr/local` PATH entries.
- `home/.zsh_functions` — **Modify**: fix `zfetch` clone error propagation + quoting.
- `config/aerospace/aerospace.toml` — **Modify**: `q` exits service mode.
- `config/git/config` — **Modify**: make `cleanup` alias non-destructive.
- `bin/dot` — **Modify**: skip empty config dirs in link/clean/backup/status (prevents the empty-`config/docker/` clobber).
- `tests/dot_link.bats` — **Modify**: add an empty-config-dir test.
- `.github/workflows/ci.yml` — **Modify**: pin actions to SHAs, add `concurrency` + `timeout-minutes`.
- Local cleanup (no commit): remove the empty `config/docker/` dir + any stale `~/.config/docker` symlink.

---

## Task 1: Zsh safety — aliases, PATH guards, zfetch

**Files:** `home/.zsh_aliases`, `home/.zshrc`, `home/.zsh_functions`

- [ ] **Step 1: Remove POSIX-shadowing aliases in `home/.zsh_aliases`**

Delete line `alias grep='grep --color=auto'` entirely. Replace the "Modern tool replacements" block:

```zsh
[[ -x "$(command -v bat)" ]] && alias cat='bat'
[[ -x "$(command -v dust)" ]] && alias du='dust' || alias du='du -h -c'
[[ -x "$(command -v procs)" ]] && alias ps='procs'
```

with non-shadowing names (never alias `cat`/`du`/`ps`):

```zsh
# Modern tool replacements — non-shadowing (never alias POSIX core commands).
[[ -x "$(command -v bat)" ]] && alias catt='bat'
[[ -x "$(command -v dust)" ]] && alias duu='dust'
[[ -x "$(command -v procs)" ]] && alias pss='procs'
```

- [ ] **Step 2: Guard the gnubin + Intel PATH entries in `home/.zshrc`**

Replace these three lines:

```zsh
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/usr/local/opt/grep/libexec/gnubin:$PATH"
export PATH="/usr/local/sbin:$PATH"
```

with directory-guarded versions (leave the `/opt/homebrew/bin` line as-is; guard the others):

```zsh
[[ -d "/opt/homebrew/opt/coreutils/libexec/gnubin" ]] && export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
[[ -d "/usr/local/opt/grep/libexec/gnubin" ]] && export PATH="/usr/local/opt/grep/libexec/gnubin:$PATH"
[[ -d "/usr/local/sbin" ]] && export PATH="/usr/local/sbin:$PATH"
```

- [ ] **Step 3: Fix `zfetch` clone error propagation in `home/.zsh_functions`**

In `zfetch`, both `git clone` branches currently do `git clone ...; if [[ $? != 0 ]]; then git_clone_error_msg $?; cd $cwd; return $?; fi` — `$?` is clobbered by `cd`, so it returns 0 on failure. Replace BOTH branches' clone+check with the captured-rc form:

For the `if [[ -n $ref ]]` branch:

```zsh
            git clone --quiet "$url" "$dest"
            local rc=$?
            if [[ $rc -ne 0 ]]; then
                git_clone_error_msg "$rc"
                cd "$cwd"
                return "$rc"
            fi

            git checkout --quiet "$ref"
            echo -e "  Checked out branch ${ref}"
```

For the `else` (depth-1) branch:

```zsh
            git clone --quiet --depth 1 "$url" "$dest"
            local rc=$?
            if [[ $rc -ne 0 ]]; then
                git_clone_error_msg "$rc"
                cd "$cwd"
                return "$rc"
            fi
            echo -e "  Checked out default branch"
```

Also quote the remaining bare expansions in `zfetch`: `cd "$cwd"` (every occurrence), `cd "$dest"`, `[[ ! -d "$dest" ]]`, `local url="https://github.com/$name.git"`, `source "$plugin"`. Leave the rest of the function intact.

- [ ] **Step 4: Verify zsh syntax + smoke**

Run: `zsh -n home/.zsh_aliases && zsh -n home/.zshrc && zsh -n home/.zsh_functions && echo SYNTAX_OK`
Expected: `SYNTAX_OK`.

Run: `dot link all -f && zsh -i -c 'alias | grep -E "^(grep|cat|du|ps)=" || echo NO_POSIX_ALIASES'`
Expected: prints `NO_POSIX_ALIASES` (none of grep/cat/du/ps are aliased). The new `catt`/`duu`/`pss` exist instead.

- [ ] **Step 5: Run the full gate**

Run: `bin/dot test`
Expected: `All checks passed`.

- [ ] **Step 6: Commit**

```bash
git add home/.zsh_aliases home/.zshrc home/.zsh_functions
git commit -m "fix(zsh): drop POSIX-shadowing aliases, guard PATH, fix zfetch errors"
```

---

## Task 2: Config safety — aerospace, git cleanup, empty-config-dir hardening

**Files:** `config/aerospace/aerospace.toml`, `config/git/config`, `bin/dot`, `tests/dot_link.bats`

- [ ] **Step 1: Fix the aerospace service-mode trap**

In `config/aerospace/aerospace.toml`, change:

```toml
q = ['enable toggle'] # disable/enable window management
```

to also return to main mode (otherwise you stay stuck in service mode):

```toml
q = ['enable toggle', 'mode main'] # disable/enable window management, then exit service mode
```

- [ ] **Step 2: Defang the destructive git `cleanup` alias**

In `config/git/config`, change:

```gitconfig
    cleanup = "!git remote prune origin && git gc && git clean -df && git stash clear"
```

to drop the irreversible `git clean -df` (deletes untracked files/dirs) and `git stash clear` (discards stashes):

```gitconfig
    cleanup = "!git remote prune origin && git gc"
```

- [ ] **Step 3: Write a failing test for empty-config-dir handling**

In `tests/dot_link.bats`, add (uses the existing `setup_sandbox` from `test_helper`):

```bash
@test "link all skips an empty config package (no symlink created)" {
  mkdir -p "$DOTFILES/config/emptypkg"
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/emptypkg" ]
}
```

- [ ] **Step 4: Run it to verify it fails**

Run: `bats tests/dot_link.bats -f "empty config"`
Expected: FAIL — `dot link` currently symlinks the empty dir, so `$XDG_CONFIG_HOME/emptypkg` exists.

- [ ] **Step 5: Make `bin/dot` skip empty config dirs**

In `bin/dot`, the config-package loops in `cmd_link`, `cmd_clean`, `cmd_backup`, and `link_status` iterate `for config in "$DOTFILES/config"/*`. Add an emptiness guard right after the existing `[[ -d "$config" ]] || continue` (or `if [ -d "$config" ]`) check in EACH loop, so an empty directory is skipped:

```bash
    # skip empty config packages (nothing to link)
    [[ -n "$(ls -A "$config" 2>/dev/null)" ]] || continue
```

Apply the same one-line guard in all four loops (link, clean, backup, status). For the `cmd_link` "specific package" path (`dot link <pkg>`), also guard: if `$DOTFILES/config/$pkg` is empty, `log_warning "Package $pkg is empty, skipping"` and return 0.

- [ ] **Step 6: Verify the test passes + remove the real empty dir**

Run: `bats tests/dot_link.bats`
Expected: all pass (including the new empty-config test).

Run (one-time local cleanup of the real empty dir + any stale link):
```bash
[[ -L "$HOME/.config/docker" ]] && rm "$HOME/.config/docker"
rmdir config/docker 2>/dev/null || true
```
(`config/docker/` is an untracked empty dir, so this is local hygiene — no commit. The `bin/dot` guard prevents recurrence.)

- [ ] **Step 7: Run the full gate + commit**

Run: `shellcheck -x bin/dot && bash -n bin/dot && shfmt -i 2 -ci -d bin/dot && echo OK && bin/dot test`
Expected: `OK` then `All checks passed`.

```bash
git add config/aerospace/aerospace.toml config/git/config bin/dot tests/dot_link.bats
git commit -m "fix(config): aerospace service-mode exit, safe git cleanup, skip empty config dirs"
```

---

## Task 3: CI hardening — SHA-pin actions, concurrency, timeouts

**Files:** `.github/workflows/ci.yml`

- [ ] **Step 1: Resolve the current SHAs for the pinned actions**

Run:
```bash
gh api repos/actions/checkout/git/ref/tags/v4 --jq '.object.sha'
gh api repos/actions/setup-python/git/ref/tags/v5 --jq '.object.sha'
```
(If the tag points at a tag object rather than a commit, dereference with `repos/actions/checkout/git/tags/<sha> --jq '.object.sha'`.) Record both commit SHAs.

- [ ] **Step 2: Pin the actions + add concurrency and timeouts**

In `.github/workflows/ci.yml`:
- Add a top-level `concurrency` block after `on:`:
  ```yaml
  concurrency:
    group: "${{ github.workflow }}-${{ github.ref }}"
    cancel-in-progress: true
  ```
- Add `timeout-minutes: 10` to each job (`checks` and `pre-commit`).
- Replace every `uses: actions/checkout@v4` with `uses: actions/checkout@<sha> # v4` and every `uses: actions/setup-python@v5` with `uses: actions/setup-python@<sha> # v5`, using the SHAs from Step 1.

- [ ] **Step 3: Validate the workflow locally**

Run: `CI=true ./bin/dot-test && echo RUNNER_CMD_OK` (the `checks` job command still passes).
Run (YAML sanity): `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML_OK')"` (or `pre-commit run check-yaml --files .github/workflows/ci.yml`).
Expected: `RUNNER_CMD_OK` and `YAML_OK`.

- [ ] **Step 4: Run the gate + commit**

Run: `bin/dot test` → `All checks passed`. `pre-commit run --all-files` → all Passed.

```bash
git add .github/workflows/ci.yml
git commit -m "ci: pin actions to commit SHAs, add concurrency and timeouts"
```

---

## Done criteria
- No interactive alias shadows `grep`/`cat`/`du`/`ps`; `catt`/`duu`/`pss` exist; gnubin/Intel PATH entries are `[[ -d ]]`-guarded.
- `zfetch` returns the real clone exit code on failure (no longer swallowed); expansions quoted.
- Aerospace `q` exits service mode; git `cleanup` no longer runs `clean -df`/`stash clear`.
- `dot link` skips empty config packages (covered by a bats test); the empty `config/docker/` is gone.
- CI actions pinned to SHAs; `concurrency` cancels superseded runs; jobs have `timeout-minutes`.
- `bin/dot test` and both CI jobs green.
