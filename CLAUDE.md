# Dotfiles Project

## Who I Am

Senior backend engineer. Primary stack: Java 25+, Spring Boot 4.x, Gradle, PostgreSQL, Kubernetes, Terraform. Also invests in Indian stock market (stocks and mutual funds). Lifelong learner. This is a personal macOS laptop.

## About This Repo

Personal dotfiles managing my macOS development environment. Clean git history, fully independent.

## Platform

- macOS only (setup script assumes Darwin)
- Apple Silicon (`/opt/homebrew`) with Intel fallback (`/usr/local`)
- `.zshrc` uses `brew shellenv` for architecture-appropriate paths

## Architecture

- `bin/dot` is the main entry point. Built-in commands: link, unlink, backup, clean, help
- `bin/dot-*` are external commands discovered via PATH (doctor, update, git, homebrew, macos, shell)
- `bin/lib/common.sh` provides shared utilities (colors, logging, spinners)
- `config/` directories are symlinked to `~/.config/` via `dot link`
- `home/` files are symlinked to `~/` preserving directory structure
- `home/.zshenv` sets XDG dirs, DOTFILES path, and is the shell entry point
- `config/zsh/.zshrc` is the main shell config, sourced after .zshenv

## Key Files

- `Brewfile` — all Homebrew packages (organized by category)
- `bin/dot` — dotfiles manager
- `bin/dot-doctor` — health check for all tools
- `bin/dot-update` — update brew, nvim, zsh plugins, sdkman, dotfiles
- `config/zsh/.zshrc` — shell config (plugins, tools, completions)
- `config/zsh/.zsh_functions` — git functions (gcom, grbm, gpum, gll), utilities
- `config/zsh/.zsh_aliases` — shell aliases
- `config/zsh/.docker_aliases` — docker/compose helpers
- `config/starship/starship.toml` — prompt config
- `config/aerospace/aerospace.toml` — tiling window manager
- `config/nvim/` — neovim config (lua, lazy.nvim)
- `config/ghostty/` — terminal emulator config
- `config/tmux/tmux.conf` — terminal multiplexer

## Rules

### Shell Scripts
- All `dot-*` scripts must have `# Description:` comment on line 2 for auto-discovery
- All scripts source `$DOTFILES/bin/lib/common.sh` for shared utilities
- Use `set -Eeuo pipefail` in all bash scripts
- Use `log_success`, `log_error`, `log_warning`, `log_info` from common.sh
- Use `run_with_spinner` for long operations
- Use `fmt_title_underline` for section headers
- Use `printf` with `%b` for ANSI color variables (not `%s`)
- Use `return 1` in functions, not `exit 1` (kills entire script under set -e)
- Never use `trap EXIT` inside functions — use explicit cleanup instead
- macOS ships BSD tools: no `readlink -f`, no GNU `sed -i`. Use ZSH `:A` modifier or `cd && pwd -P`
- Every script must work on a fresh machine (day 0): guard tools with `command -v`, files with `[[ -f ]]`
- `git config <key>` returns exit 1 if key missing — always use `2>/dev/null || true`

### Brewfile
- Organized by category with comments: macOS, core, shell, dev tools, infra
- `cask` entries go inside `if OS.mac?` block
- Every entry needs a trailing comment explaining what it is
- No deprecated taps (homebrew/bundle is built-in now)

### Zsh Config
- `.zshrc` is sectioned with `########` comment blocks
- Profiler hooks wrap the entire file (start at top, stop at bottom)
- `.zsh_functions` has its own `compinit -C` (cached) because `compdef` calls require it, and the file is sourced BEFORE `.zshrc`'s compinit
- Homebrew completions before compinit
- compinit with 24h caching
- Plugin keybindings must come AFTER the plugin's `zfetch` call, not in the Key Bindings section
- `fzf-git.sh` requires `[[ -o zle ]]` guard — it registers zle widgets at source time
- Tool initializations check `command -v` before running
- SDKMAN must be at the end (it modifies PATH)
- Starship init is the very last thing
- Never alias POSIX core commands (`find`, `grep`, `sed`, `awk`, `sort`) — other tools call them internally (SDKMAN uses `find`, etc.)
- After any zsh config change, verify with: `zsh -i -c 'echo ok' 2>&1`

### Git Functions
- Auto-detect main/master via `git remote show origin`
- Check for uncommitted changes before destructive operations
- All functions support `-h`/`--help`

### Aerospace
- Workspaces: D=Dev, W=Web, C=Chat, M=Mail, N=Notes, S=Productivity, Z=Zoom
- App assignments use `if.app-id` (bundle identifiers)
- Floating layout for system dialogs (Finder, System Preferences)

### Config Management
- `bin/dot` clean and backup arrays must match actual config directories
- When adding a new config package: add to both arrays and test `dot link`/`dot backup`

### Local Customization
- `~/.localrc` and `~/.zshrc.local` — machine-specific shell config (sourced by .zshrc, not committed)
- `~/.zshenv.local` — machine-specific env vars (sourced by .zshenv, not committed)
- `~/.gitconfig-local` — personal git config (name, email, signing key)

### Common Commands
```bash
dot link all -v           # Symlink everything
dot doctor                # Verify all tools installed
dot update all            # Update brew, nvim, zsh, sdkman, dotfiles
dot backup -v             # Backup before changes
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
- Scope examples: `brew`, `zsh`, `dot`, `aerospace`, `nvim`
