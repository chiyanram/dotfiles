# Terminal Experience Overhaul — Design Spec

**Date:** 2026-06-18
**Owner:** Chiyanram (senior backend engineer — Java/Spring/Gradle/K8s/Terraform, macOS Apple Silicon, work + personal laptops)
**Status:** Approved design, pending spec review → implementation plan

## 1. Goal

Turn the Ghostty + tmux + sesh + starship stack from "structurally correct" (where the config audit left it) into a terminal that is **fast to work in and genuinely good-looking**, identical across the work and personal laptops because it is config-as-code in this repo. Four dimensions, one cohesive design: visual polish, shell history, session/project switching, in-terminal navigation.

## 2. Decisions locked during brainstorming

- **Terminal:** Ghostty is the daily driver. Warp is retired as the primary (its settings are app-managed and not reproducible across machines). No Warp config work.
- **Scope:** all four experience dimensions (A–D below), plus a tools-foundation layer.
- **Background look:** subtle glass — `background-opacity = 0.95` + `background-blur-radius = 24`. Tunable; not opaque, not heavy glass.
- **Font:** keep Monaspace Neon (+ Radon italics), ligatures on. Add an explicit Nerd Font symbol fallback so glyphs are always crisp and intentional rather than relying on implicit fallback.
- **History:** atuin, **local-only** — no cloud or cross-profile sync (work/personal command history never leaves the machine or crosses profiles).
- **Splits:** **tmux owns all panes/splits/copy-mode.** Ghostty's split keybinds are removed; Ghostty owns windows, tabs, and the quick-terminal only. One mental model.

## 3. Non-goals (out of scope)

- Warp configuration (abandoned as daily driver).
- Cloud or cross-machine history sync (atuin stays local; self-hosted personal-only sync is a possible *future* spec).
- Changing the font family or the catppuccin palette.
- Neovim changes (already done in the nvim overhaul).
- New tmux/ghostty *features* beyond what these four dimensions require (YAGNI).

## 4. Global constraints

- macOS only, Apple Silicon primary. Every tool here (ghostty, atuin, sesh, fonts) is macOS-resident.
- **Work/personal isolation:** atuin DB is local and gitignored; no history sync. Nothing machine-specific or secret is committed.
- **zshrc ordering rules** (from the project CLAUDE.md) are binding: Homebrew completions before `compinit`; tool inits guarded by `command -v`; **SDKMAN stays last; starship init stays the very last thing.** atuin's init must sit *before* starship and after compinit. Plugin keybindings come after the plugin's `zfetch`/init, not in the Key Bindings section.
- Never alias/shadow POSIX core commands. BSD-safe shell (no `readlink -f`/GNU `sed -i`). Bash scripts keep `set -Eeuo pipefail`, `return 1` in functions.
- **Reproducible across laptops:** every change lives in the repo and is applied by `dot link`. The only non-versioned step is granting macOS Accessibility permission for the Ghostty global hotkey (documented, per-machine, one-time).
- Validation gates: `ghostty +validate-config` (or a clean load), tmux config parses, `zsh -i -c 'echo ok'` is clean, `atuin --version` resolves, and `bin/dot test` + `pre-commit run --all-files` stay green. Conventional Commits; no `Co-Authored-By`.

## 5. Design

### Layer 0 — Tools foundation
The top-8 from `docs/audit/tool-shortlist.md` are already in `brew/Brewfile.core` but **not installed**. This layer runs `dot homebrew bundle` to install them. The one strictly required by this design is **atuin** (Layer B); the rest (tenv, kubeconform, trivy, git-absorb, tflint, fx, grpcurl) are general wins installed in the same pass. The fuller menu in the shortlist stays a later, opt-in decision.

### A — Visual polish (`config/ghostty/config`, `config/tmux/`, `config/starship/starship.toml`)
- **Transparency:** uncomment and set `background-opacity = 0.95`, `background-blur-radius = 24`.
- **Font fallback:** add an explicit `Symbols Nerd Font Mono` (or the installed FiraCode Nerd Font) as a secondary `font-family` so icon glyphs are crisp; keep Monaspace Neon primary, Radon italics, `font-feature = +liga`.
- **Window polish:** balanced, slightly larger window padding; keep `cursor-style = block` + `cursor-invert-fg-bg`; set catppuccin-matched selection colors; refine tab-bar styling (macOS native tabs already via `macos-titlebar-style`).
- **Theme cohesion:** verify and align the catppuccin-macchiato hex values used by Ghostty's theme, the tmux statusline (`config/tmux/themes/catppuccin*`), and the starship palette (the macchiato hexes already in `starship.toml`) so all three render the *same* colors. Where they diverge, standardize on macchiato.

### B — History that thinks (`config/atuin/config.toml` new, `home/.zshrc`)
- New `config/atuin/config.toml`: `auto_sync = false`, `update_check = false`, a compact inline search UI (`style`, `inline_height`), sensible `search_mode`/`filter_mode` (e.g. fuzzy, scoped to directory by default with a toggle to global).
- `home/.zshrc`: add `command -v atuin >/dev/null && eval "$(atuin init zsh)"` positioned **after compinit, before starship**. atuin binds `Ctrl-R` and Up-arrow by default (its core strength); this is the default here, documented, with `--disable-up-arrow` noted as the one-line opt-out.
- First-run: `atuin import auto` pulls existing zsh history so nothing is lost. The atuin DB lives under XDG data and is gitignored.
- Interaction with fzf: atuin takes over `Ctrl-R` from fzf; fzf keeps `Ctrl-T` (files) and `Alt-C` (dirs). Documented so the handoff is intentional, not a surprise.

### C — Session & project switching (`config/sesh/sesh.toml`, `config/tmux/tmux.conf`, `config/ghostty/config`)
- **sesh:** populate `[[session]]` entries for frequent projects (e.g. dotfiles, primary work/personal repos) with `startup_command`s; keep the blacklist. Bind a tmux popup to the sesh picker (e.g. `bind o` → `display-popup ... sesh connect "$(sesh list | fzf)"`), zoxide-ranked. Optionally a shell-level zle widget on a free chord for "jump to project" outside tmux.
- **Ghostty quick-terminal:** add a global hotkey `keybind = global:ctrl+grave=toggle_quick_terminal` (quake-style dropdown), with `quick-terminal-position = top` and a short animation. Requires one-time macOS Accessibility permission (documented). This is the "shell now, from any app" reflex.

### D — In-terminal navigation (`config/ghostty/config`, `config/tmux/tmux.conf`, `home/.zshrc`)
- **Remove Ghostty split keybinds** (`cmd+s>\`, `cmd+s>-`, `cmd+s>j/k/h/l`, `cmd+s>z`, `cmd+s>e`). **Keep** the tab keybinds (`new_tab`, `next/previous_tab`, `move_tab`, `goto_tab:N`) and `shift+enter`.
- **tmux owns panes:** the existing `bind |`/`bind -` splits and `select-pane h/j/k/l` stay. Add seamless vim-aware pane navigation (`Ctrl-h/j/k/l` that respects whether nvim is focused) so moving between editor splits and tmux panes is one motion.
- **Clipboard:** tmux copy-mode `y → pbcopy` already wired; keep. Consider Ghostty copy-on-select as an opt-in.
- **fzf-everywhere:** fzf (`Ctrl-T`, `Alt-C`) + `fzf-git.sh` (already sourced, branches/commits/stashes/files on `Ctrl-G` chords) + atuin (`Ctrl-R`). Ensure the keybind set is consistent and documented in one place.

## 6. Architecture / unit boundaries

Each layer is an independently shippable change with its own validation:
- **Layer 0** touches only the Brewfile install step — no config edits.
- **A** is pure config (ghostty/tmux/starship), validated by config-load + visual confirmation.
- **B** is atuin config + one guarded zshrc init line, validated by `zsh -i -c 'echo ok'` + `atuin` resolving + Ctrl-R behavior.
- **C** is sesh + tmux popup + one ghostty global keybind, validated by tmux parse + a sesh picker launch + the dropdown toggling.
- **D** is keybind surgery (ghostty removals + tmux additions), validated by tmux parse + ghostty load + a manual keymap walkthrough.

The shared seams are the **catppuccin palette** (A wires it across three tools) and the **keybinding map** (C and D both touch ghostty/tmux keybinds) — which is why these ship as one cohesive spec rather than separate ones.

## 7. Testing & rollout

- **Automated gates** (in `bin/dot test` / pre-commit where applicable): toml/yaml validity for atuin/sesh/ghostty-adjacent files, `zsh -i -c 'echo ok'` clean, tmux config parse, shellcheck on any touched scripts.
- **Tool-resolves checks:** `atuin --version`, `sesh --version`, `ghostty +validate-config`.
- **Manual confirmation (noted per layer, owner verifies in-app):** the glass look renders; icons are crisp; `Ctrl-R` opens atuin with imported history; the sesh picker jumps projects; the quick-terminal drops down (after granting Accessibility); tmux owns splits and Ghostty no longer splits; `Ctrl-h/j/k/l` moves seamlessly between nvim and tmux.
- **Per-laptop:** the global hotkey needs a one-time macOS Accessibility grant — documented in the README terminal section. Everything else applies via `dot link` + `exec zsh`.

## 8. Open implementation details (resolved at plan time, not blockers)

- Exact ghostty fallback font name (`Symbols Nerd Font Mono` vs the installed `FiraCode Nerd Font`) — pick whichever is present and renders the starship/tmux glyph set.
- Exact quick-terminal hotkey if `ctrl+grave` collides on the work laptop — fall back to `cmd+ctrl+grave`.
- Whether to add `tmux-plugins`/a vim-tmux-navigator dependency for `Ctrl-hjkl` vs a self-contained `is_vim` inline binding — prefer the self-contained inline version (no new plugin) unless it proves brittle.
