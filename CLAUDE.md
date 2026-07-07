# Dotfiles Project

## How We Work Here

Mirrors my global instructions (dev-kit `AGENTS.md`) — repeated because these bite most in a bash/dotfiles repo:

- **Never speculate as fact.** Every claim about the code or a tool is VERIFIED (ran/read it — cite `file:line`) or INFERRED ("I think / haven't checked"). A guess dressed as fact is the costliest failure here.
- **Don't call it done until it's green.** "fixed / passing / works" are VERIFIED claims — run the `bats` test or command and show the output. No run, no claim.
- **Feedback-loop-first debugging.** Before hypothesizing, build one deterministic command that goes red on _this_ bug and green once fixed. No red-capable repro → no hypothesis.
- **Small, deliberate steps** — each increment demoable or bats-testable on its own.
- **DRY / single source of truth** — state each convention once in its canonical home; flag repetition aggressively.
- **Challenge, don't flatter; lead with a recommendation, not a menu.**

Process:

- **Every issue gets a branch.** Non-trivial work is tracked by a GitHub issue and done on its own branch (`<type>/<issue-number>-<brief-description>`) — never commit straight to `main`. No issue yet → log one first.
- **Work in a worktree by default.** Concurrent Claude sessions run on this repo — do all branch work in an isolated worktree (`.claude/worktrees/`); the shared checkout stays on `main` and is never branch-switched. Inside a worktree the test gate is `./bin/dot-test` (see Tests).
- **Commit small, focused pieces** on the branch, pushing as you go. One logical change per commit; never batch unrelated changes.
- **Close the issue through a PR.** Open a PR with `Closes #N` in the body and squash-merge to `main`; the merge is what closes the issue (a `Closes #N` commit only takes effect once it lands on `main`).
- **Every change updates its docs.** A behavior/command/config change updates the relevant docs (`README.md`, this file, `usage()` help) in the _same_ change — doc drift is a bug.

## About This Repo

Personal dotfiles for my macOS laptop (backend engineer: JVM toolchain via SDKMAN, Node/Python via mise). Clean git history, fully independent. Who I am and how I work live in the global instructions (dev-kit `AGENTS.md`) — this file only holds what's specific to this repo.

## Platform

- macOS only (setup script assumes Darwin)
- Apple Silicon (`/opt/homebrew`) with Intel fallback (`/usr/local`)
- `.zshrc` uses `brew shellenv` for architecture-appropriate paths

## Architecture

- `bin/dot` is the main entry point. Built-in commands: link, unlink, backup, restore, clean, help
- `bin/dot-*` are external commands discovered via PATH — `dot help` lists them; don't enumerate them in docs (the list goes stale)
- `bin/lib/common.sh` provides shared utilities (colors, logging, spinners)
- `config/` directories are symlinked to `~/.config/` via `dot link`
- `home/` files are symlinked to `~/` preserving directory structure
- `home/.zshenv` sets XDG dirs, DOTFILES path, and is the shell entry point
- `home/.zshrc` is the main shell config, sourced after .zshenv (no ZDOTDIR — zsh reads rc files from \$HOME so installer-added lines work)

## Key Files

- `brew/Brewfile.core` — cross-profile Homebrew packages; `brew/Brewfile.{personal,work}` — profile-specific
- `bin/dot` — dotfiles manager
- `bin/dot-doctor` — health check for all tools
- `bin/dot-update` — update brew, nvim, zsh plugins, sdkman, dotfiles
- `home/.zshrc` — shell config (plugins, tools, completions)
- `home/.zsh_functions` — zfetch plugin manager, git functions (gcom, grbm, gpum, gll), navigation (c, h, g, md), utilities
- `home/.zsh_aliases` — shell aliases
- `home/.docker_aliases` — docker/compose helpers
- `home/.zprofile` — login-shell env (brew shellenv, installer-added PATHs)
- `config/starship/starship.toml` — prompt config
- `config/nvim/` — neovim config (lua, lazy.nvim)
- `config/ghostty/` — terminal emulator config
- `config/tmux/tmux.conf` — terminal multiplexer

## Rules

### Shell Scripts

- All `dot-*` scripts must have `# Description:` comment on line 2 for auto-discovery
- All scripts source `$DOTFILES/bin/lib/common.sh` for shared utilities
- Use `set -Eeuo pipefail` in all bash scripts
- Use `log_success`, `log_error`, `log_warning`, `log_info` from common.sh
- Use `run_with_spinner` for long operations — it detaches the child's stdin (`</dev/null`) so an unattended step is deterministically non-interactive regardless of job-control context (a prompting tool like SDKMAN's `sdk upgrade` reads EOF and takes its default); never rely on an interactive prompt in a `dot-*` step. The one exception is sudo, which prompts on `/dev/tty`, not stdin: the spinner scans for a sudo descendant every tick and pauses with a password banner for **every** prompt (a step may sudo repeatedly, e.g. brew once per cask) — a missed pause means the `\r` redraw erases `Password:` and the step reads as hung
- Use `fmt_title_underline` for section headers
- Use `printf` with `%b` for ANSI color variables (not `%s`)
- Use `return 1` in functions, not `exit 1` (kills entire script under set -e)
- Never use `trap EXIT` inside functions — use explicit cleanup instead
- macOS ships BSD tools: no `readlink -f`, no GNU `sed -i`. Use ZSH `:A` modifier or `cd && pwd -P`
- Every script must work on a fresh machine (day 0): guard tools with `command -v`, files with `[[ -f ]]`
- The day-0 path (`bootstrap.sh` → `setup.sh` → `dot-*`) runs under macOS system **bash 3.2** until Homebrew installs bash 5.x, so those scripts must be bash-3.2-safe: no associative arrays (`declare -A`), `mapfile`/`readarray`, or `${x,,}`/`${x^^}` case-conversion. A process never swaps its own interpreter mid-run — to check a freshly-installed bash, probe the PATH `bash` (`bash -c 'echo "${BASH_VERSINFO[0]}"'`), not `$BASH_VERSINFO`
- Install Homebrew with the TTY-preserving `bash -c "$(curl … install.sh)"`, never `curl … | bash` — a fresh Mac's install needs an interactive sudo password, which a pipe (stdin = the pipe, not the terminal) can't provide
- Never `source` a third-party init script (sdkman-init.sh etc.) into a dot script's own process — they expand unset vars (fatal under `set -u`, and the abort escapes the step runner's `||` catch, killing the whole script) and may use bash-4-only syntax. Run the tool in a PATH-bash subprocess instead: `bash -c 'source …init.sh && tool "$@"' tool "$@"`
- `git config <key>` returns exit 1 if key missing — always use `2>/dev/null || true`

### Tests

- Tests are bats; `dot test` is the merge gate (shellcheck, shfmt, prettier-markdown, bash syntax, zsh smoke, bats) — run it before claiming green
- `dot-test` always tests its own tree, ignoring an inherited `DOTFILES` env var — in a worktree, run `./bin/dot-test` (the PATH `dot test` is the main checkout's and tests main)
- Tests must be bash-3.2-safe too: the macOS CI job installs no modern bash, so bats runs under system bash 3.2 — no bash-4+ features (`$BASHPID`, etc.)
- shfmt house style is `-i 2 -ci` — enforced by `dot test` and CI but NOT by pre-commit, so hooks passing ≠ CI passing
- Markdown is formatted by prettier: a pre-commit hook auto-formats `.md` on commit, and `dot test` runs the same pinned prettier in `--check` mode — keep the version in `bin/dot-test` in sync with the `mirrors-prettier` rev in `.pre-commit-config.yaml`

### Brewfile (`brew/Brewfile.*`)

- Organized by category with comments: macOS, core, shell, dev tools, infra
- `cask` entries go inside `if OS.mac?` block
- Every entry needs a trailing comment explaining what it is
- No deprecated taps (homebrew/bundle is built-in now)
- Env vars read in a Brewfile (`ENV.fetch(...)`) must use the `HOMEBREW_` prefix — Homebrew strips non-`HOMEBREW_*` vars from the environment

### Zsh Config

- `.zshrc` is sectioned with `########` comment blocks
- Profiler hooks wrap the entire file (start at top, stop at bottom)
- `compdef` calls live in `.zshrc` after compinit (not in `.zsh_functions` — it is sourced before compinit)
- Before removing any line, grep for everything it provides — e.g. `compinit` provides `compdef`/`compadd`; dropping it silently breaks callers in the earlier-sourced `.zsh_functions`
- Homebrew completions before compinit
- compinit with 24h caching
- Plugin keybindings must come AFTER the plugin's `zfetch` call, not in the Key Bindings section
- `fzf-git.sh` requires `[[ -o zle ]]` guard — it registers zle widgets at source time
- Tool initializations check `command -v` before running
- mise activates Node/Python runtimes (reads .nvmrc/.python-version natively)
- SDKMAN is lazy-loaded (candidate bins on PATH, full init deferred) and must stay at the end
- Starship init is the very last thing
- Never alias POSIX core commands (`find`, `grep`, `sed`, `awk`, `sort`) — other tools call them internally (SDKMAN uses `find`, etc.)
- After any zsh config change, verify with: `zsh -i -c 'echo ok' 2>&1`

### Git Functions

- Auto-detect main/master via `git remote show origin`
- Check for uncommitted changes before destructive operations
- All functions support `-h`/`--help`

### Config Management

- `bin/dot` clean and backup dynamically derive the config list from `$DOTFILES/config/*/`
- No hardcoded arrays — adding a new config package only requires creating the directory

### Local Customization

- `~/.localrc` and `~/.zshrc.local` — machine-specific shell config (sourced by .zshrc, not committed)
- `~/.zshenv.local` — machine-specific env vars (sourced by .zshenv, not committed)
- `~/.gitconfig-local` — personal git config (name, email, signing key)
- Identity/auth/transport git config (`url.insteadOf`, keys, email) must NEVER go in `config/git/config` — it's shared across machines; use `~/.gitconfig-local`

### Common Commands

```bash
dot link all -v           # Symlink everything
dot doctor                # Verify all tools installed
dot update all            # Update brew, nvim, zsh, sdkman, dotfiles
dot backup -v             # Backup before changes
dot test                  # Full gate: shellcheck, shfmt, prettier-markdown, bash syntax, zsh smoke, bats (CI runs exactly this)
bats tests/<file>.bats    # Run a single test file
dot profile get           # Machine profile (personal|work) — stored in ~/.config/dotfiles/profile, selects Brewfile
dot homebrew bundle       # Install all Brewfile packages
pre-commit run --all-files  # Validate configs
```

### What Not to Commit

- `.idea/`, `.zcompdump-*`, `ohmyzsh/`, `*.DS_Store` (covered by .gitignore)
- Plan files (`plan_*.md`) — ephemeral, not for git
- Secrets, tokens, credentials

### Conventional Commits

- feat: new tool, command, or config
- fix: bug fix in scripts or configs
- chore: cleanup, removals, maintenance
- refactor: restructure without behavior change
- docs: README and documentation updates
- Scope examples: `brew`, `zsh`, `dot`, `nvim`

## Agent skills

### Issue tracker

Issues live in GitHub Issues (`gh` CLI); external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles use their default names (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
