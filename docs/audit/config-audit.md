# Config Audit — 2026-06-18

A full audit of every config package against the goal: **crisp, deliberate, non-fragile config that fits a senior Java / Spring Boot / Kubernetes / Terraform / PostgreSQL backend engineer on macOS** — with the copied-from-elsewhere cruft removed.

Findings are grouped by area and tagged **[H]** high / **[M]** med / **[L]** low. Each has a concrete fix. The end of the doc has a **prioritized implementation plan**; nothing here is applied yet — this is for your review.

---

## 1. Zsh shell (`home/.zshrc`, `.zshenv`, `.zprofile`, `.zsh_functions`, `.zsh_aliases`, `.docker_aliases`)

### High
- **[H] `coreutils` gnubin on PATH unconditionally** (`.zshrc`) — prepending `/opt/homebrew/opt/coreutils/libexec/gnubin` puts GNU `ls/find/sed/awk` ahead of BSD tools globally. This is the *same* fragility your own rule warns about (POSIX-command shadowing breaks SDKMAN's `find`, scripts assuming BSD `sed`). → guard with `[[ -d … ]] &&` and document, or drop it and add only the specific tools you need (`gdate`).
- **[H] POSIX-command aliases** (`.zsh_aliases`) — `grep='grep --color=auto'`, `du='dust'`, `ps='procs'`, `cat='bat'` all violate the "never alias POSIX core commands" rule and silently break tools/scripts that call them. → remove; use distinct names (`duu`, `pss`, `catt`) or `bat --style=plain`.
- **[H] `zfetch` swallows clone failures** (`.zsh_functions`) — `return $?` runs *after* `cd $cwd`, so `$?` is the `cd` status (0), not the failed `git clone`. Clone errors are reported then silently succeed. → `local rc=$?; cd "$cwd"; return $rc`; also quote `$dest/$url/$ref/$name` and `local`-scope the color vars.

### Med
- **[M] Intel `/usr/local` PATH/fpath entries on Apple Silicon** (`.zshenv`, `.zshrc`) — `/usr/local/share/zsh/site-functions`, `/usr/local/opt/grep/libexec/gnubin`, `/usr/local/sbin` don't exist on `/opt/homebrew`; pollute PATH/fpath. → guard with `[[ -d ]]` or remove.
- **[M] `eval $(brew shellenv)` unquoted** (`.zprofile`) — missing quotes around the command substitution. → `eval "$(…brew shellenv)"`.
- **[M] `MANROFFOPT='-c'` contradicts the `LESS_TERMCAP_*` colors** (`.zshrc`) — `-c` disables the very man-page colors being configured. → drop `MANROFFOPT='-c'`; or use `bat` as the man pager and delete the whole `LESS_TERMCAP_*` block.
- **[M] `pyenv` block ordering** (`.zshrc`) — `PYENV_ROOT/bin` is added to PATH *inside* the `command -v pyenv` guard, so on a fresh install the guard never fires. → move `PYENV_ROOT` + PATH prepend outside the guard.
- **[M] `SHARE_HISTORY` + `INC_APPEND_HISTORY` both set** (`.zshrc`) — mutually exclusive; SHARE supersedes INC. → remove `INC_APPEND_HISTORY`.
- **[M] `local var=$(cmd)` masks exit codes** (`.zsh_functions` `grbm`/`gpum`) — `local` always returns 0. → split: `local x; x=$(cmd)`.
- **[M] nav helpers `c`/`h`/`md`/`g`** — unquoted `$1`, no `-h/--help`, no `$CODE_DIR` guard; `g` uses string `>` not `-gt`. → quote, add help, `[[ $# -gt 0 ]]`.
- **[M] `.docker_aliases` arg-dropping** — `d-aws-cli-fn` and `drun-fn` hardcode `"$1" "$2" "$3"`, silently dropping extra args. → use `"$@"` / `"${@:2}"`. `dip-fn`'s `OUT` isn't `local`.

### Low (dead/floated)
- `CACHEDIR` duplicates `XDG_DATA_HOME`; `VIM_TMP` is a dead Vim artifact; `typeset -aU path` in `.zshenv` is premature/redundant; Linuxbrew block in `.zprofile` is dead; `LOCAL_OPTIONS`/`LOCAL_TRAPS`/`CORRECT`/`IGNORE_EOF` are cargo-culted (document or drop); LS-color detection block is a dead BSD branch; `fnm --use-on-cd` adds latency to every `cd`; `zsh-npm-scripts-autocomplete` plugin is frontend-only; `pubkey`/`claude` aliases use UUOC / hardcoded `$HOME`.

**Health:** Structurally sound (XDG, compinit caching, plugin guards). The three high items (gnubin PATH, POSIX aliases, zfetch) are the real fragility; fixing them + the `local var=$(…)` pattern makes it genuinely non-fragile.

---

## 2. Neovim (`config/nvim/`)

**This is a lightly-personalized fork of `nicknisi`'s dotfiles.** ~40% of LSP servers, ~30% of treesitter parsers, all snippets, and several plugins target a web/PHP/Ruby stack irrelevant to you — and the config you'd actually want (Java/Terraform/K8s) is missing. **Recommendation: trim-to-fit (don't rebuild)** — the lua architecture (blink.cmp, snacks, gitsigns, telescope, treesitter, lazy.nvim) is solid.

### High — remove web/PHP/Ruby cruft
- LSP servers: drop `eslint`, `ts_ls`, `denols`, `astro`, `intelephense` (PHP), `tailwindcss`, `ruby_lsp` (mass-installed by mason every machine).
- Formatters (conform): strip JS/TS/CSS/Ruby/PHP entries (prettier/stylelint/rubocop/pint); keep `sh`, `python`, `go`, `lua`.
- Treesitter `ensure_installed`: drop `astro`, `blade`, `pug`, `ruby`, `tsx`, `typescript`, `jsdoc`, `json5`, `css`.
- Delete `after/queries/blade/*` (Laravel) + the fragile custom blade parser install.
- Remove `vuki656/package-info.nvim` (npm), `telescope-node-modules.nvim` + `<leader>fn`, `nvim-colorizer` `tailwind=true`, JS/TS snippet files, `tpope/vim-ragtag` (HTML/XML).

### High — add the stack you actually use
- **`nvim-jdtls` + `jdtls`** (Eclipse JDT) — the single highest-value addition; includes Java DAP. Currently NO Java LSP at all.
- **`terraformls` + `tflint`** + `terraform_fmt` (conform).
- **`yamlls` + `schemastore.nvim`** with K8s/Helm/GH-Actions schemas; `helm_ls`.
- Treesitter: add `java`, `hcl`, `dockerfile`, `sql` (optional `kotlin`, `groovy`).

### High — active bugs
- `statusline.lua` references `lazyvim.util` (this is NOT LazyVim) → will error; remove the block.
- `copilot-cmp` hard-depends on `nvim-cmp` (commented out) → errors; use copilot native `suggestion` mode.
- `vim-vsnip`/`cmp-vsnip` deadweight (blink.cmp is active) → remove; point blink at the `snippets/` dir.

### Med/Low
- Duplicate `pylsp` in servers; stray `vim.notify("Using new definition handler")`; `vim.loop`→`vim.uv`, `get_active_clients`→`get_clients` (deprecated); `<C-s>`/`<D-s>` defined 5× each; `nvim-treesitter/playground` archived (use `:InspectTree`); mason-lspconfig pinned `^1.0.0` (v2 API available); 6 legacy vimscript files duplicate lua (`hiinterestingword`, `zoom`, `winmove`, `applylocalsettings`, `numbers`, `autoload/functions`) + `ftplugin/ruby.vim`/`html.vim`, `ftdetect/html.vim` (EJS), `nicknisi` dashboard art still default; `<leader>sr` sniprun/spectre collision.

---

## 3. Terminal stack (`config/ghostty/`, `config/tmux/`, `config/sesh/`)

### High
- **[H] Ghostty `shell-integration-features` declared twice** — second wins; `no-cursor` on the first line is dead. → keep one.
- **[H] tmux `default-terminal "${TERM}"`** — passes through whatever TERM the parent has (often `xterm-256color`), losing 24-bit color. → `set -g default-terminal "tmux-256color"` + `set -as terminal-features ",xterm-ghostty:RGB:usstyle"` (fixes true-color + undercurl inside Ghostty+tmux).
- **[H] sesh vs `tm` split** — sesh is installed + partially configured but bypassed by the hand-rolled `tm` fzf script (reinvents ~80% of sesh). → **pick one**; sesh (zoxide-ranked sessions, startup commands, tmux popup) is the higher-value choice, or commit to `tm` and drop sesh from the Brewfile.

### Med
- Ghostty `cmd+s` splits shadow tmux panes (two pane systems); tmux `escape-time 0` breaks alt-keys (→ `10`); `aggressive-resize` deprecated (→ `window-size latest`); `nerdwin` reads `@tmux-nerd-font-window-name-*` options never set; copy-mode-vi has no `y` yank to `pbcopy`; `status-interval` unset (15s) while `tm_tunes` forks `osascript` every refresh; sesh blacklist glob `*` only one level deep.

### Low
- Ghostty `window-decoration`/padding zeroes are defaults; `bold-is-bright` likely unwanted in catppuccin; tmux `bind r` and theme reload hardcode `~/.config`; dead `default.conf`/`bubbles.conf` themes; `send-prefix` bound twice.

---

## 4. Window manager + prompt (`config/aerospace/`, `config/starship/`)

### High
- **[H] Aerospace service-mode trap** — `q = ['enable toggle']` leaves you stuck in service mode. → `q = ['enable toggle', 'mode main']`.
- **[H] Starship: no Terraform module** — Terraform workspace (default/staging/prod) is invisible. → add `$terraform` to the format + `[terraform]` block.

### Med
- 18 numbered-workspace bindings (`alt-1..9` + move) with no app-assignment backing — dead vs the named-workspace model; Starship K8s `detect_files` `"k8s"`/`"kubernetes"` are no-ops (detect_files matches files, not dirs) → fix trigger or `context_from_config = true`; `[kotlin]` always-on noise on Gradle-Kotlin projects → `disabled = true`; AWS/GCP context unconfigured (will appear unexpectedly if env vars set); `command_timeout = 1000` too tight for K8s context on VPN → 2000; IntelliJ bundle-id may be wrong (verify via `aerospace list-apps`).

### Low
- `username`/`hostname` configured but absent from the format string (dead); `[gradle]` redundant with `[java]`; empty `after-login/startup-command` arrays; missing float rules for Activity Monitor/Console.

---

## 5. Git + CLI tools (`config/git/`, `config/ripgrep/`, `config/lazygit/`, `config/docker/`)

> `git-delta` **is** fully wired (`core.pager`, `[delta]`, `interactive.diffFilter`, lazygit) — good. The git config is genuinely well-crafted (rerere, zdiff3, autoSquash, updateRefs, histogram diff).

### High
- **[H] empty `config/docker/` dir** — `dot link` symlinks `~/.config/docker/` to an empty dir, displacing Docker's real `config.json` (credentials/registry auth) → silent auth failures. → remove `config/docker/` from the repo, or populate a tracked template.
- **[H] global gitignore useless for your stack** (`config/git/ignore`) — 20 lines, no `.idea/`, `.terraform/`, `*.tfstate*`, `target/`, `.gradle/`, `build/`, `*.iml`. → add Java/Spring/Terraform/IntelliJ entries; drop stale vim/coc lines.
- **[H] `cleanup` git alias is destructive** — runs `git clean -df` + `git stash clear` silently (irreversible). → add `-n` dry-run or remove.

### Med/Low
- lazygit `os.editPreset: ""` → `"nvim"` (jump-to-line); lazygit config is a near-verbatim upstream copy (deprecated `os.*`/log fields, no `customCommands`); ripgrep types are JS/pug/graphql-heavy → swap for java/kotlin/gradle/tf; git aliases: `pnb` redundant (autoSetupRemote), `update` assumes `upstream` + uses backticks, `SEPERATOR` typo, `[color "sh"]` dead (you use starship), 4 redundant `color.<x> = auto` lines, `pull.rebase` + `autosetuprebase` redundant; add `pull.ff = only`.

---

## 6. Repo + CI hygiene (`.github/`, `.pre-commit-config.yaml`, `bin/` legacy, `bootstrap.sh`, `README.md`, `.gitignore`)

### High
- **[H] CI actions on mutable tags** — `actions/checkout@v4`, `actions/setup-python@v5` → pin to commit SHAs (supply-chain + ends the Node20 deprecation warnings).

### Med
- `git-clc` typo `--apprev-ref` → silently wrong clipboard copy; CI has no `concurrency` cancel-in-progress, no `timeout-minutes`, no macOS job, no pip cache, shfmt curl unverified (no checksum); pre-commit shellcheck excludes all legacy `bin/` utilities (broaden `files` to `^bin/`); `bin/t` (React/Jest) + `bin/update` (superseded by `dot update`) are dead; bootstrap `xcode-select` poll loop can hang forever (add max-retry); `config/zsh/` shows untracked in `git status` (gitignore or delete).

### Low
- No `shfmt` pre-commit hook (only in `dot test`); README has a duplicated "Manual Setup" heading + a `bin/dot` vs `./bin/dot` inconsistency; several legacy scripts use `function name()` (SC2112), `#!/bin/bash` hardcoded paths, or `set -e` only; `bin/battery`/`bin/hl` are dead/template.

**Dead/removable legacy `bin/`:** `t` (React/Jest), `update` (superseded), `battery` (only in a commented tmux line), `hl` (template). **Keep + gate under shellcheck (broaden the pre-commit `files` to `^bin/`):** `tm`, `nerdwin`, `wgh`, `pt`, `jwt`, `git-*`, `digest` (macOS-only), `toggle-menu-bar`, `colortest`, `fromhex`, `extract`, `isdir`, `isfile`, `confirm`.

---

## Prioritized implementation plan

Ordered by value × safety. Each cluster is an independently shippable change with its own tests/gate.

**P1 — correctness/safety (do first):**
1. Remove the empty `config/docker/` dir (prevents Docker-credential clobbering). **[H]**
2. Zsh: drop the POSIX aliases (`grep/du/ps/cat`), guard the coreutils gnubin PATH, fix `zfetch` error propagation + quoting. **[H]**
3. Aerospace service-mode `q` fix; git `cleanup` alias guard. **[H]**
4. CI: pin actions to SHAs + add `concurrency`/`timeout-minutes`. **[H]**

**P2 — fit-to-stack (high value):**
5. Neovim trim-to-fit: remove web/PHP/Ruby LSP/formatter/parser/snippet/plugin cruft + fix the 3 active bugs. **[H]**
6. Neovim add: `nvim-jdtls`, `terraformls`+`tflint`, `yamlls`+schemastore (K8s), `helm_ls`, treesitter `java/hcl/dockerfile/sql`. **[H]**
7. Starship: add `$terraform`, fix K8s `detect_files`, disable `[kotlin]`, raise `command_timeout`. **[H/M]**
8. Global gitignore: add Java/Terraform/IntelliJ entries. **[H]**
9. tmux/Ghostty true-color: `tmux-256color` + `terminal-features` RGB/undercurl; de-dupe Ghostty `shell-integration-features`. **[H]**

**P3 — decisions (need your call):**
10. **sesh vs `tm`** — commit to one (recommend sesh). **[H, decision]**
11. Broaden shellcheck to all `bin/`; remove dead `bin/` scripts (`t`, `update`, `battery`, `hl`); fix `git-clc` typo. **[M]**

**P4 — polish (low):**
12. The many low-severity floated/dead-config removals across zsh/git/lazygit/aerospace/tmux/README.

I recommend doing P1 + P2 as the next plan(s); P3 needs your decisions; P4 is a sweep. See `tool-shortlist.md` for the tooling additions (which pair with the nvim/starship/terraform work).
