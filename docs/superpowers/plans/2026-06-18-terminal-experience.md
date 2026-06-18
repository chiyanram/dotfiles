# Terminal Experience Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the already-correct Ghostty + tmux + sesh + starship stack into a terminal that is fast to work in and genuinely good-looking, applied as config-as-code so it is identical on the work and personal laptops.

**Architecture:** Four small, independent config layers on top of the existing stack — visual polish (Ghostty), atuin history (local-only), quick-terminal + sesh sessions, and navigation cleanup. No new shell framework; each layer is a focused edit to existing config files plus, where needed, one new config file. Spec: `docs/superpowers/specs/2026-06-18-terminal-experience-design.md`.

**Tech Stack:** Ghostty (text config), tmux, sesh, starship, zsh, atuin, Homebrew (Brewfile), Nerd Fonts.

## Global Constraints

- macOS only, Apple Silicon. Every tool here is macOS-resident. The repo applies via `dot link`; only the global-hotkey Accessibility grant is a manual per-machine step.
- **Work/personal isolation:** atuin is local-only (`auto_sync = false`) — history never leaves the machine or crosses profiles. Never commit secrets. The atuin DB lives under `~/.local/share/atuin/` (outside the repo).
- **zshrc ordering is binding:** Homebrew completions before `compinit`; tool inits guarded by `command -v`; **SDKMAN stays its existing block (line ~238); starship init stays the very last thing (line ~246).** atuin's init goes AFTER the fzf block (so atuin owns `Ctrl-R`) and BEFORE the SDKMAN/starship blocks.
- Never alias/shadow POSIX core commands. BSD-safe. Preserve the `.zshrc` profiler hooks + `########` sections; no section reordering.
- **Validation gates (run per task as noted):** `zsh -i -c 'echo ok'` prints `ok` with no errors; Ghostty config shows no errors; tmux config parses; `bin/dot test` and `pre-commit run --all-files` stay green. Conventional Commits; **no `Co-Authored-By`**.
- **Keep these active settings** (do not "clean up"): `bold-is-bright`, `copy-on-select`, the existing tab keybinds, the existing prefix pane-nav (`prefix h/j/k/l`).

## Prerequisite (run once, before Task 1)

The top-8 tools are already in `brew/Brewfile.core` but not installed. Install them (atuin is required by Task 2; the other seven are general wins, no config needed):

```bash
cd /Users/chiyanram/tools-repo/dotfiles
dot homebrew bundle
command -v atuin && atuin --version    # confirm atuin is now present
```

## File structure

| File | Responsibility | Tasks |
|------|----------------|-------|
| `config/ghostty/config` | emulator look + tab/quick-terminal keybinds (splits removed) | 1, 3, 4 |
| `brew/Brewfile.core` | add the symbols-only Nerd Font for glyph fallback | 1 |
| `config/atuin/config.toml` (new) | atuin behaviour, local-only | 2 |
| `home/.zshrc` | atuin init (after fzf, before SDKMAN) + fzf keymap comment | 2, 4 |
| `config/sesh/sesh.toml` | pinned project sessions | 3 |
| `config/tmux/tmux.conf` | smart pane nav + clear-screen rebind | 4 |
| `README.md` | document the quick-terminal Accessibility grant + keymap | 3 |

---

## Task 1: Visual polish (Ghostty look)

Covers spec §5-A. Subtle glass, crisp glyph fallback, breathing-room padding. Lowest-risk, most-visible win.

**Files:**
- Modify: `config/ghostty/config`
- Modify: `brew/Brewfile.core`

**Interfaces:**
- Consumes: nothing.
- Produces: a `Symbols Nerd Font Mono` fallback that later tasks don't depend on.

- [ ] **Step 1: Add the symbols-only Nerd Font to the Brewfile**

Monaspace has no icon glyphs; a dedicated symbols-only Nerd Font is the clean fallback (keeps Monaspace letterforms, supplies only the icons). In `brew/Brewfile.core`, find the fonts area (search for `cask` font entries; if none, add under the macOS cask block). Add:

```ruby
cask 'font-symbols-only-nerd-font'     # icon glyph fallback for Monaspace (starship/tmux symbols)
```

Then install it:

```bash
cd /Users/chiyanram/tools-repo/dotfiles && dot homebrew bundle
```

- [ ] **Step 2: Verify the fallback font's exact family name**

Run:
```bash
ghostty +list-fonts 2>/dev/null | grep -i 'symbols nerd' | head
```
Expected: a line containing `Symbols Nerd Font Mono` (or `Symbols Nerd Font`). Use the EXACT name it prints in Step 3. If nothing prints, fall back to the installed `FiraCode Nerd Font Mono` (confirm with `ghostty +list-fonts | grep -i firacode`).

- [ ] **Step 3: Add the font fallback line**

In `config/ghostty/config`, the primary font is line 30: `font-family = "Monaspace Neon Regular"`. Add a second `font-family` line immediately after it (Ghostty treats additional `font-family` entries as ordered fallbacks):

```
font-family = "Monaspace Neon Regular"
font-family = "Symbols Nerd Font Mono"
```
(Use the exact name from Step 2.)

- [ ] **Step 4: Turn on subtle glass**

In `config/ghostty/config`, lines 6-7 are commented:
```
# background-opacity = 0.75
# background-blur-radius = 40
```
Replace those two lines with the approved values (uncommented):
```
background-opacity = 0.95
background-blur-radius = 24
```

- [ ] **Step 5: Add breathing-room padding**

After line 14 (`window-padding-balance = false`), add:
```
window-padding-x = 12
window-padding-y = 10
```

- [ ] **Step 6: Verify palette cohesion (no edit unless divergent)**

Confirm all three already use catppuccin macchiato:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
grep -n 'catppuccin-macchiato' config/ghostty/config        # ghostty theme
grep -rn 'macchiato\|catppuccin' config/tmux/tmux.conf       # tmux sources catppuccin
grep -c '#8aadf4\|#c6a0f6\|#a6da95' config/starship/starship.toml   # starship uses macchiato hexes
```
Expected: ghostty theme is macchiato; tmux sources `themes/catppuccin/*`; starship hex count > 0. They already match — this is a verify step. If a hex diverges from the macchiato palette, note it in the report; do not restyle.

- [ ] **Step 7: Validate the Ghostty config loads clean**

Run:
```bash
ghostty +show-config >/dev/null 2>/tmp/ghostty-err.txt; echo "exit=$?"; cat /tmp/ghostty-err.txt
```
Expected: `exit=0` and `/tmp/ghostty-err.txt` is empty (no error/warning lines). A non-empty file means a bad key/value — fix it.

Run: `bin/dot test 2>&1 | tail -1` → `All checks passed`. Run: `pre-commit run --all-files 2>&1 | tail -5` → all hooks Passed.

**Manual confirmation (owner, in-app):** reload Ghostty (`Cmd+Shift+,`) → background is subtly translucent + blurred, icons in the prompt/tmux bar are crisp, padding looks balanced.

- [ ] **Step 8: Commit**

```bash
git add config/ghostty/config brew/Brewfile.core
git commit -m "feat(ghostty): subtle glass, nerd-font glyph fallback, padding"
```

---

## Task 2: atuin — history that thinks

Covers spec §5-B. Local-only, fuzzy, directory-aware; atuin owns `Ctrl-R` and up-arrow; imports existing zsh history.

**Files:**
- Create: `config/atuin/config.toml`
- Modify: `home/.zshrc`

**Interfaces:**
- Consumes: atuin binary (installed in the Prerequisite).
- Produces: an `atuin init zsh` block in `.zshrc`; no later task depends on it.

- [ ] **Step 1: Confirm atuin is installed**

Run: `command -v atuin && atuin --version`. Expected: a version string. If missing, run `cd /Users/chiyanram/tools-repo/dotfiles && dot homebrew bundle` first.

- [ ] **Step 2: Create the atuin config (local-only)**

Create `config/atuin/config.toml`:
```toml
## atuin — magical shell history. https://docs.atuin.sh
## LOCAL-ONLY: history never syncs off this machine or across work/personal profiles.
auto_sync = false
update_check = false

## UI
style = "compact"
inline_height = 25
show_preview = true
show_help = true

## Behaviour
search_mode = "fuzzy"
filter_mode = "global"
## Up-arrow scopes results to the current directory (Ctrl-R stays global).
filter_mode_shell_up_key_binding = "directory"
## Fill the command line on Enter instead of auto-running it (avoids accidental re-runs).
enter_accept = false
```

- [ ] **Step 3: Verify the new config is valid TOML**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
python3 -c "import tomllib,sys; tomllib.load(open('config/atuin/config.toml','rb')); print('toml ok')"
```
Expected: `toml ok`.

- [ ] **Step 4: Symlink the atuin config**

`config/*` dirs are symlinked to `~/.config/` by `dot link`:
```bash
cd /Users/chiyanram/tools-repo/dotfiles && dot link atuin -v
ls -l ~/.config/atuin/config.toml    # → symlink into the repo
```
Expected: `~/.config/atuin/config.toml` points into `…/dotfiles/config/atuin/config.toml`. (If `dot link atuin` isn't a valid form, run `dot link all -v` — it's idempotent.)

- [ ] **Step 5: Add the atuin init to `.zshrc` (after fzf, before SDKMAN)**

Read `home/.zshrc` around lines 189-240. The fzf init block ends near line 193 (`source <(fzf --zsh)`) with its closing `fi`. Immediately AFTER that block's `fi`, and BEFORE the `# SDKMAN (must be at end)` block (line ~238), insert:
```zsh

########################################################
# atuin — searchable shell history
########################################################
# After fzf so atuin owns Ctrl-R; before SDKMAN/starship per ordering rules.
if [[ -x "$(command -v atuin)" ]]; then
    eval "$(atuin init zsh)"
fi
```

- [ ] **Step 6: Import existing zsh history (one-time)**

Run:
```bash
atuin import auto
```
Expected: it reports importing from the zsh history file (`$HISTFILE`). Nothing is lost; existing history becomes searchable.

- [ ] **Step 7: Verify the shell loads clean and atuin owns Ctrl-R**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
zsh -i -c 'echo ok' 2>&1
zsh -i -c 'bindkey | grep -i atuin' 2>/dev/null
```
Expected: first prints `ok` (no new errors; the pre-existing fzf `zle` subshell warnings may appear and are unrelated). The second shows `Ctrl-R` (`^R`) bound to an `atuin` widget.

Run: `bin/dot test 2>&1 | tail -1` → `All checks passed`. Run: `pre-commit run --all-files 2>&1 | tail -5` → Passed (check-toml validates the new file).

**Manual confirmation (owner):** open a shell, press `Ctrl-R` → atuin's compact search opens with your imported history; press Up → results scope to the current directory.

- [ ] **Step 8: Commit**

```bash
git add config/atuin/config.toml home/.zshrc
git commit -m "feat(atuin): local-only searchable shell history"
```

---

## Task 3: Quick-terminal + pinned sesh sessions

Covers spec §5-C. Ghostty quake-style dropdown on a global hotkey; sesh pinned projects (the sesh popup itself is already bound at `tmux.conf:104`).

**Files:**
- Modify: `config/ghostty/config`
- Modify: `config/sesh/sesh.toml`
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing from Tasks 1-2.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Add the Ghostty quick-terminal + global hotkey**

In `config/ghostty/config`, before the `config-file = ?./overrides` line (line 74), add a section:
```
# Quick-terminal: quake-style dropdown from any app (needs macOS Accessibility grant once)
quick-terminal-position = top
quick-terminal-animation-duration = 0.15
keybind = global:ctrl+grave=toggle_quick_terminal
```
Note: if `ctrl+grave` collides on the work laptop, the fallback is `global:cmd+ctrl+grave` — put that in the machine-local `config/ghostty/overrides` file rather than changing this line.

- [ ] **Step 2: Pin the dotfiles project in sesh**

`config/sesh/sesh.toml` has commented `[[session]]` examples. Add one stable, cross-laptop entry (the picker already surfaces other frequent dirs via zoxide ranking, so only pin ones that need a startup command):
```toml
[[session]]
name = "dotfiles ⚙️"
path = "~/tools-repo/dotfiles"
startup_command = "nvim"
```
Leave the existing commented template above it so the owner can pin work/personal repos per machine.

- [ ] **Step 3: Document the Accessibility grant + quick-terminal in the README**

In `README.md`, under the tmux/terminal area (search for `### tmux` ~line 187), add a short subsection after it:
```markdown
### Ghostty quick-terminal

A quake-style dropdown toggles from any app with `Ctrl`+`` ` ``. macOS requires a one-time
Accessibility grant for the global hotkey: **System Settings → Privacy & Security →
Accessibility → enable Ghostty.** If `Ctrl`+`` ` `` collides on a machine, override it in
`~/.config/ghostty/overrides` with `keybind = global:cmd+ctrl+grave=toggle_quick_terminal`.
```

- [ ] **Step 4: Validate**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
ghostty +show-config >/dev/null 2>/tmp/ghostty-err.txt; echo "exit=$?"; cat /tmp/ghostty-err.txt
python3 -c "import tomllib; tomllib.load(open('config/sesh/sesh.toml','rb')); print('sesh toml ok')"
bin/dot test 2>&1 | tail -1
pre-commit run --all-files 2>&1 | tail -5
```
Expected: ghostty `exit=0` + empty error file; `sesh toml ok`; `All checks passed`; hooks Passed.

**Manual confirmation (owner):** grant Accessibility, then press `Ctrl`+`` ` `` from another app → Ghostty drops down from the top. In tmux, `prefix s` → sesh picker shows the pinned `dotfiles ⚙️` entry.

- [ ] **Step 5: Commit**

```bash
git add config/ghostty/config config/sesh/sesh.toml README.md
git commit -m "feat(ghostty): quick-terminal dropdown; pin dotfiles sesh session"
```

---

## Task 4: Navigation cleanup

Covers spec §5-D. Resolve the double-split-system by removing Ghostty's split keybinds (tmux owns panes), add smart Vim-aware `Ctrl-hjkl` pane nav, and document the fzf-everywhere keymap. **This task changes keybindings — the owner should confirm the keymap (shown in the handoff) before merge.**

**Files:**
- Modify: `config/ghostty/config`
- Modify: `config/tmux/tmux.conf`
- Modify: `home/.zshrc`

**Interfaces:**
- Consumes: nothing.
- Produces: the final keymap.

- [ ] **Step 1: Remove Ghostty's split keybinds (keep tabs)**

In `config/ghostty/config`, update the comment on lines 42-43 and remove the split keybinds, keeping all tab keybinds (lines 47-61). Specifically:

Change the comment block (lines 42-43) from:
```
# Split keybindings
# These are similar to tmux, but with the prefix being cmd+s
```
to:
```
# Tab keybindings (cmd+s leader). Splits are owned by tmux, not Ghostty.
```

Delete these lines (the split actions):
```
keybind = cmd+s>\=new_split:right
keybind = cmd+s>-=new_split:down
```
and:
```
keybind = cmd+s>j=goto_split:bottom
keybind = cmd+s>k=goto_split:top
keybind = cmd+s>h=goto_split:left
keybind = cmd+s>l=goto_split:right

keybind = cmd+s>z=toggle_split_zoom
keybind = cmd+s>e=equalize_splits
```
Keep the `new_tab`, `next_tab`, `previous_tab`, `move_tab`, and `goto_tab:N` keybinds.

- [ ] **Step 2: tmux — replace redundant window-nav with smart pane nav + keep clear-screen**

In `config/tmux/tmux.conf`, the lines 87-88 are an alternate window-nav that duplicates tmux's default `prefix n`/`prefix p`:
```tmux
bind -r C-h select-window -t :-
bind -r C-l select-window -t :+
```
Replace those two lines with the Vim-aware smart pane navigation (root-level, no prefix) plus a clear-screen rebind onto the prefix (since root `C-l` now navigates):
```tmux
# Smart pane nav (Ctrl-h/j/k/l, no prefix) — passes through to Vim when a Vim-like
# process owns the pane, otherwise switches tmux panes. (prefix n/p still switch windows.)
is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
    | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf)(diff)?$'"
bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h' 'select-pane -L'
bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j' 'select-pane -D'
bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k' 'select-pane -U'
bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l' 'select-pane -R'
# Root C-l now moves panes; clear the screen with prefix C-l.
bind C-l send-keys 'C-l'
```
(The existing `prefix h/j/k/l` pane-select and `prefix H/J/K/L` resize stay as-is.)

- [ ] **Step 3: Document the fzf-everywhere keymap in `.zshrc`**

In `home/.zshrc`, immediately after the fzf init block (the `source <(fzf --zsh)` area, ~line 193) and before the atuin block added in Task 2, add a comment block (no behavior, documentation so the keymap is discoverable):
```zsh
# Keymap — fuzzy everything:
#   Ctrl-R  atuin (history)      Ctrl-T  fzf (files)      Alt-C  fzf (cd dir)
#   Ctrl-G  fzf-git (branches/commits/stashes/files — see fzf-git.sh)
```

- [ ] **Step 4: Validate**

Run:
```bash
cd /Users/chiyanram/tools-repo/dotfiles
ghostty +show-config >/dev/null 2>/tmp/ghostty-err.txt; echo "ghostty exit=$?"; cat /tmp/ghostty-err.txt
tmux -L p13nav -f "$DOTFILES/config/tmux/tmux.conf" new-session -d -s _c 2>&1 && tmux -L p13nav kill-server 2>/dev/null && echo "tmux parse OK"
zsh -i -c 'echo ok' 2>&1 | tail -1
bin/dot test 2>&1 | tail -1
pre-commit run --all-files 2>&1 | tail -5
```
Expected: ghostty `exit=0` + empty error file; `tmux parse OK`; `ok`; `All checks passed`; hooks Passed.

**Manual confirmation (owner):** Ghostty `cmd+s>\` no longer splits (tmux `prefix |`/`prefix -` do); `Ctrl-h/l` moves between tmux panes; inside nvim the same keys pass through; `prefix C-l` clears the screen; `prefix n`/`prefix p` still switch windows.

- [ ] **Step 5: Commit**

```bash
git add config/ghostty/config config/tmux/tmux.conf home/.zshrc
git commit -m "refactor(nav): tmux owns splits; smart vim-aware pane nav; fzf keymap"
```

---

## Done criteria
- Ghostty shows a subtle glass background with crisp glyphs and balanced padding; config loads with no errors.
- `Ctrl-R` opens atuin (local-only, imported history); `zsh -i -c 'echo ok'` is clean.
- The quick-terminal drops down on the global hotkey (after the documented Accessibility grant); `prefix s` lists the pinned sesh session.
- Ghostty no longer splits; tmux owns panes; `Ctrl-hjkl` navigates panes/vim; `prefix C-l` clears; `prefix n`/`prefix p` switch windows; the fzf keymap is documented.
- `bin/dot test` and `pre-commit run --all-files` stay green throughout. Owner has confirmed the Task 4 keymap.
- All four layers ship as separate commits; the catppuccin palette and the keybinding map remain coherent across Ghostty + tmux + starship.
