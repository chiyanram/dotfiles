# Dotfiles Polish Sweep — Implementation Plan (Plan 13)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Remove the remaining dead/floated config and fix the low-severity bugs the audit surfaced (zsh cargo-cult, git-config cruft, dead tmux themes, README duplicate heading), and harden the lint gate by broadening shellcheck to every `bin/` script — completing the audit's P4 polish + the deferred P3 #11.

**Architecture:** Pure cleanup. Three independent sweeps: (1) zsh dead-config + bug fixes, (2) git/tmux/README cosmetics, (3) broaden the pre-commit shellcheck gate to all `bin/` scripts after fixing the two scripts that currently fail it. No new features, no behavior the owner relies on is removed — genuinely subjective active settings (`bold-is-bright`, the `ls --color` fallback, `setopt CORRECT`/`IGNORE_EOF`) are KEPT (documented, not dropped). Each task ends green on `bin/dot test` + `pre-commit run --all-files`.

**Tech Stack:** zsh, git config, tmux, pre-commit + shellcheck, bash.

## Global Constraints
- macOS-only, Apple Silicon primary. All scripts stay BSD-safe; bash scripts keep `set -Eeuo pipefail`, `return 1` not `exit 1` in functions, no `trap EXIT` in functions.
- **Never alias or shadow POSIX core commands** (`find`/`grep`/`sed`/`awk`/`sort`/`cat`/`ls`/`rm`/`cp`/`mv`).
- Never commit secrets. Work/personal identity files stay out of git. Use `trash`, not `rm -rf`, for any path deletion. Tracked-file deletions use `git rm`.
- **After ANY zsh change, the load gate is:** `zsh -i -c 'echo ok' 2>&1` prints `ok` with no errors.
- `bin/dot test` stays green; `pre-commit run --all-files` stays green. Conventional Commits; NO `Co-Authored-By`.
- Preserve the `.zshrc` profiler hooks (top + bottom) and its `########` section blocks. Do not reorder sections.
- This is a polish sweep: remove only DEAD config (unused/no-op/duplicate) and fix BUGS. When a setting is an active preference rather than dead, document it — do not silently change behavior.

## Reference spec
`docs/audit/config-audit.md` — §1 (zsh Low + the two folded-in Med items: Intel `/usr/local` fpath, unquoted `eval $(brew shellenv)`), §5 (git config Med/Low), §3/§4 Low (tmux), §6 (README + broaden shellcheck to `^bin/`). Exact current text for every edit is inlined below — do not hunt for it.

---

## Task 1: Zsh dead-config + bug sweep

**Files:**
- Modify: `home/.zshenv`
- Modify: `home/.zprofile`
- Modify: `home/.zshrc`
- Modify: `home/.zsh_aliases`

**Interfaces:**
- Consumes: `XDG_DATA_HOME` (set in `.zshenv:6` = `$HOME/.local/share`) replaces the duplicate `CACHEDIR`. `ZPLUGDIR` in `.zshrc` currently falls back through `CACHEDIR`; after this task it falls back through `XDG_DATA_HOME`.
- Produces: nothing downstream depends on the removed vars.

- [ ] **Step 1: Pre-flight — confirm nothing else uses the vars being removed**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
grep -rn 'VIM_TMP\|CACHEDIR' config/nvim/ home/ 2>/dev/null
```
Expected: the only `CACHEDIR` hits are in `home/.zshenv` and `home/.zshrc` (handled below); `VIM_TMP` hits only in `home/.zshenv`. If `config/nvim/` references either var, STOP and report — do not remove that var; note it in the report and skip its removal.

- [ ] **Step 2: `home/.zshenv` — drop `CACHEDIR`, `VIM_TMP`, the premature `typeset -aU path`, and guard the Intel fpath entry**

Current `.zshenv` lines 18-19:
```sh
export CACHEDIR="$HOME/.local/share"
export VIM_TMP="$HOME/.vim-tmp"
```
Remove both lines (the `# add a config file for ripgrep` comment + `RIPGREP_CONFIG_PATH` line that follow stay).

Current lines 23-24:
```sh
[[ -d "$CACHEDIR" ]] || mkdir -p "$CACHEDIR"
[[ -d "$VIM_TMP" ]] || mkdir -p "$VIM_TMP"
```
Replace BOTH lines with a single XDG_DATA_HOME guard (so the data dir is still created):
```sh
[[ -d "$XDG_DATA_HOME" ]] || mkdir -p "$XDG_DATA_HOME"
```

Current lines 28-31 (Intel `/usr/local` fpath, dead on Apple Silicon — folded-in §1 Med):
```sh
fpath=(
    /usr/local/share/zsh/site-functions
    $fpath
)
```
Replace with a guarded prepend:
```sh
# Intel Homebrew zsh site-functions (skipped on Apple Silicon /opt/homebrew)
[[ -d /usr/local/share/zsh/site-functions ]] && fpath=(/usr/local/share/zsh/site-functions $fpath)
```

Current line 33:
```sh
typeset -aU path
```
Remove it (`.zshrc` already runs `typeset -U path` before PATH is consumed).

- [ ] **Step 3: `home/.zprofile` — remove the dead Linuxbrew branch, quote the two `eval $(...)` (folded-in §1 Med)**

Current lines 4-14:
```sh
if [[ -f /opt/homebrew/bin/brew ]]; then
    # Homebrew exists at /opt/homebrew for arm64 macos
    eval $(/opt/homebrew/bin/brew shellenv)
elif [[ -f /usr/local/bin/brew ]]; then
    # or at /usr/local for intel macos
    eval $(/usr/local/bin/brew shellenv)
elif [[ -d /home/linuxbrew/.linuxbrew ]]; then
    # or from linuxbrew
    test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
    test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
```
Replace with (drop the Linuxbrew `elif`, quote both command substitutions):
```sh
if [[ -f /opt/homebrew/bin/brew ]]; then
    # Homebrew exists at /opt/homebrew for arm64 macos
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
    # or at /usr/local for intel macos
    eval "$(/usr/local/bin/brew shellenv)"
fi
```

- [ ] **Step 4: `home/.zshrc` — repoint `ZPLUGDIR`, drop the two no-op setopts, document `CORRECT`/`IGNORE_EOF`, remove `MANROFFOPT`, remove the npm-scripts plugin, drop `fnm --use-on-cd`**

First read `home/.zshrc` lines 20-30, 60-80, 140-165, 198-215 so each edit lands on the right line (line numbers below are from the audit and may have drifted by ±2).

**(a)** `ZPLUGDIR` fallback (audit line 25):
```sh
export ZPLUGDIR="${CACHEDIR:-$HOME/.local/share}/zsh/plugins"
```
→
```sh
export ZPLUGDIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
```

**(b)** Remove the two global no-op setopts (audit lines 68-69) — `LOCAL_OPTIONS`/`LOCAL_TRAPS` only have effect *inside* a function that sets them, so setting them at top level does nothing:
```sh
setopt LOCAL_OPTIONS
setopt LOCAL_TRAPS
```
Delete both lines.

**(c)** Document the two remaining behavior setopts (audit lines 73 + 76) — KEEP them, add a one-line comment above each so they are no longer floated:
```sh
setopt CORRECT
```
→
```sh
# CORRECT: offer to fix a mistyped command name (e.g. "correct 'gti' to 'git'?")
setopt CORRECT
```
and
```sh
setopt IGNORE_EOF
```
→
```sh
# IGNORE_EOF: a stray Ctrl-D won't close the shell; type `exit` instead
setopt IGNORE_EOF
```

**(d)** Remove `MANROFFOPT='-c'` (audit line 202) — `-c` disables the very `LESS_TERMCAP_*` man-page colors configured just below it. Delete only this line; KEEP the `LESS_TERMCAP_*` block:
```sh
export MANROFFOPT='-c'
```

**(e)** Remove the frontend-only npm-scripts plugin (audit line 144). Delete the `zfetch` line AND any plugin keybinding line immediately following it that references the plugin (read the 2 lines after it; if the next line is a `bindkey`/`zle` tied to npm-scripts, delete it too):
```sh
zfetch grigorii-zander/zsh-npm-scripts-autocomplete
```

**(f)** Drop the per-`cd` latency hook from fnm (audit line 160) — keep fnm working, just don't re-evaluate on every directory change (this owner is Java-primary):
```sh
eval "$(fnm env --use-on-cd)"
```
→
```sh
eval "$(fnm env)"
```

- [ ] **Step 5: `home/.zsh_aliases` — fix the `pubkey` UUOC and de-hardcode the `claude` path**

Current line 66:
```sh
alias pubkey='cat ~/.ssh/id_ed25519.pub | pbcopy && echo "Public key copied to clipboard"'
```
→ (drop the useless `cat`; redirect instead — note this does NOT alias `cat`, it removes a `cat` call)
```sh
alias pubkey='pbcopy < ~/.ssh/id_ed25519.pub && echo "Public key copied to clipboard"'
```

Current line 73 (hardcoded `/Users/chiyanram`):
```sh
alias claude='claude --plugin-dir /Users/chiyanram/claude/backend-engineer-kit'
```
→ (portable across the owner's work + personal laptops)
```sh
alias claude='claude --plugin-dir $HOME/claude/backend-engineer-kit'
```

- [ ] **Step 6: Verify zsh loads clean**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
zsh -i -c 'echo ok' 2>&1
```
Expected: prints `ok`, NO errors/warnings (a "command not found", "no such file", or parse error means an edit broke sourcing — fix it).

Run: `bin/dot test 2>&1 | tail -1` → `All checks passed`.
Run: `pre-commit run --all-files 2>&1 | tail -5` → all hooks Passed (trailing-whitespace / end-of-file-fixer / shellcheck / gitleaks).

- [ ] **Step 7: Commit**

```bash
git add -A home/.zshenv home/.zprofile home/.zshrc home/.zsh_aliases
git commit -m "refactor(zsh): drop dead config, fix manroff colors, de-hardcode aliases"
```

---

## Task 2: Git config + tmux + README cosmetics

**Files:**
- Modify: `config/git/config`
- Modify: `config/tmux/tmux.conf`
- Delete: `config/tmux/themes/bubbles.conf`, `config/tmux/themes/default.conf`
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: nothing downstream.

- [ ] **Step 1: `config/git/config` — remove redundant/dead entries and the typo**

Read `config/git/config` first to confirm line positions. Apply each:

**(a)** Remove the `pnb` alias (audit line 19) — `push.autoSetupRemote = true` already does this:
```ini
	pnb = "!git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD)"
```
Delete the line.

**(b)** Fix the `update` alias backticks → `$(...)` (audit line 86), keep its behavior:
```ini
	update = !git fetch upstream && git rebase upstream/`git rev-parse --abbrev-ref HEAD`
```
→
```ini
	update = !git fetch upstream && git rebase "upstream/$(git rev-parse --abbrev-ref HEAD)"
```

**(c)** Fix the `SEPERATOR` typo (audit line 30) in the `separator` alias body:
```ini
	separator = "commit --allow-empty -m \"--------SEPERATOR--------\""
```
→
```ini
	separator = "commit --allow-empty -m \"--------SEPARATOR--------\""
```

**(d)** Remove the dead `[color "sh"]` section (audit lines 138-140) — this colorizes git's `__git_ps1` prompt, which is unused (starship renders the prompt):
```ini
[color "sh"]
	branch = yellow
```
Delete the section header and its body line.

**(e)** Remove the four redundant per-command color toggles under `[color]` (audit lines 120-124) — `ui = auto` already covers them. KEEP `ui = auto`; delete these four:
```ini
	diff = auto
	status = auto
	branch = auto
	interactive = auto
```

**(f)** Remove the redundant `autosetuprebase` (audit line 148) — `[pull] rebase = true` already makes pulls rebase globally. Under `[branch]`, delete:
```ini
	autosetuprebase = always
```
Leave `[pull] rebase = true` (line 151) as-is. Do NOT add `pull.ff = only` — it conflicts with rebase-on-pull.

- [ ] **Step 2: `config/tmux/tmux.conf` — drop the duplicate send-prefix bind**

The prefix is `C-a` (line 25). Two send-prefix binds exist (lines 26-27); keep the canonical `prefix C-a → literal C-a`, remove the second:
```tmux
bind-key a send-prefix
```
Delete only that line. Keep `bind C-a send-prefix`.

- [ ] **Step 3: Remove the two dead tmux theme files**

Neither is `source`d in `tmux.conf` (only `themes/catppuccin/*` + `themes/catppuccin.conf` are). Remove the unused ones:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
git rm config/tmux/themes/bubbles.conf config/tmux/themes/default.conf
```

- [ ] **Step 4: `README.md` — rename the duplicated "Manual Setup" heading**

Two `### Manual Setup` headings exist (line 15 = clone manually; line 59 = run setup steps individually). Keep the first; rename the SECOND (the one at ~line 59, immediately above "If you prefer to run steps individually:"):
```markdown
### Manual Setup
```
→
```markdown
### Running Steps Individually
```

- [ ] **Step 5: Verify**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
git config -f config/git/config --list >/dev/null && echo "git-config OK"
grep -n 'bubbles.conf\|default.conf' config/tmux/tmux.conf || echo "no dead-theme refs"
grep -c '^### Manual Setup$' README.md   # expect: 1
bin/dot test 2>&1 | tail -1
pre-commit run --all-files 2>&1 | tail -5
```
Expected: `git-config OK`; `no dead-theme refs`; the README count is `1`; `All checks passed`; all pre-commit hooks Passed.

- [ ] **Step 6: Commit**

```bash
git add -A config/git/config config/tmux/tmux.conf README.md
git commit -m "chore(config): trim redundant git aliases, dead tmux themes, dup readme heading"
```

---

## Task 3: Broaden shellcheck to all `bin/` scripts

Covers config-audit §6 ("broaden the pre-commit `files` to `^bin/`") + the deferred P3 #11. Two legacy scripts currently fail shellcheck; fix them first, then widen the gate so every `bin/` bash/sh script is linted on every commit. The one zsh script (`bin/git-clc`) is excluded — shellcheck cannot lint zsh.

**Files:**
- Modify: `bin/digest`
- Modify: `bin/git-bare-clone`
- Modify: `.pre-commit-config.yaml`

**Interfaces:**
- Consumes: nothing.
- Produces: a wider lint gate; no runtime behavior change to the scripts.

- [ ] **Step 1: Fix `bin/digest` shellcheck findings**

Read `bin/digest` first. Fix each (do not change behavior):
- **SC2155** (declare-and-assign masks the command's exit status) at the two `local x=$(...)` sites (~lines 134, 194). Split each into a declaration then an assignment, e.g.:
  ```bash
  local all_files=$(find ...)
  ```
  →
  ```bash
  local all_files
  all_files=$(find ...)
  ```
  Apply the same split to the `local size=$(...)` at ~line 194.
- **SC2254** (unquoted expansion in a `case` pattern) at ~line 90 (`$pattern)`): quote the pattern word — `"$pattern")` — unless the glob is intentional; if the case genuinely needs globbing, add `# shellcheck disable=SC2254` with a one-line reason on the line above. Prefer quoting.
- **SC2034** (`scope_text` assigned but never used) at ~line 140: if the variable is truly unused, remove its assignment; if it is used indirectly (e.g. via `eval`/printf later), add `# shellcheck disable=SC2034` with a reason. Read the surrounding lines to decide — prefer removal.

- [ ] **Step 2: Fix `bin/git-bare-clone` shellcheck findings**

Read `bin/git-bare-clone`. It declares a color palette (`RED ORANGE BLUE PURPLE CYAN` at ~line 29) that is never referenced → **SC2034** ×5. Remove the unused color variables (keep any color var that IS referenced elsewhere in the script — check with `grep -n` for each name before deleting). If the whole palette is unused, delete the whole block.

- [ ] **Step 3: Confirm the two scripts now pass cleanly**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
shellcheck bin/digest bin/git-bare-clone && echo "both clean"
```
Expected: `both clean` (no output from shellcheck before it).

- [ ] **Step 4: Broaden the pre-commit shellcheck `files:` regex**

In `.pre-commit-config.yaml`, the shellcheck hook is currently:
```yaml
      - id: shellcheck
        files: '^(bin/dot|bin/dot-[^/]+|bin/lib/[^/]+\.sh|setup\.sh|bootstrap\.sh)$'
```
Replace with (every top-level `bin/` script + `bin/lib/*.sh` + the two root scripts, excluding the zsh `git-clc`):
```yaml
      - id: shellcheck
        files: '^(bin/[^/]+|bin/lib/[^/]+\.sh|setup\.sh|bootstrap\.sh)$'
        exclude: '^bin/git-clc$'
```

- [ ] **Step 5: Run the broadened gate and fix anything it flags**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
pre-commit run shellcheck --all-files 2>&1 | tail -30
```
Expected: `Passed`. The gap-analysis found only `digest` + `git-bare-clone` failing under `shellcheck -x`; the hook runs without `-x`, so it may additionally surface SC1090/SC1091 (can't-follow-source) on a script that `source`s a dynamic path. If so, add a targeted `# shellcheck source=/dev/null` (or `disable=SC1091`) directive on the offending `source` line in that specific script, with a one-line reason — do NOT add `args: [-x]` globally (it changes behavior for the already-passing scripts). Re-run until `Passed`. Report every script touched.

- [ ] **Step 6: Full gate**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
bin/dot test 2>&1 | tail -1
pre-commit run --all-files 2>&1 | tail -8
```
Expected: `All checks passed`; every pre-commit hook Passed.

- [ ] **Step 7: Commit**

```bash
git add -A bin/digest bin/git-bare-clone .pre-commit-config.yaml
git commit -m "ci(shellcheck): lint all bin/ scripts; fix digest and git-bare-clone findings"
```

---

## Done criteria
- `zsh -i -c 'echo ok'` prints `ok` with no errors; the removed zsh vars/opts/plugin are gone; `CORRECT`/`IGNORE_EOF` remain but documented; man-page colors work (`MANROFFOPT='-c'` gone); `pubkey`/`claude` aliases are clean + portable.
- `config/git/config` has no `pnb`, no `[color "sh"]`, no redundant `= auto` toggles, no `autosetuprebase`, no `SEPERATOR` typo, and `update` uses `$(...)`; the duplicate tmux `send-prefix` and the two dead theme files are gone; README has exactly one `### Manual Setup`.
- The pre-commit shellcheck gate covers every `bin/` bash/sh script (zsh `git-clc` excluded); `bin/digest` and `bin/git-bare-clone` are clean; `pre-commit run --all-files` and `bin/dot test` are green.
- Intentionally RETAINED (active preferences, not dead — noted for the owner): ghostty `bold-is-bright`, the `ls --color` fallback block, `setopt CORRECT`/`IGNORE_EOF`, fnm itself (only the `--use-on-cd` latency hook dropped).
