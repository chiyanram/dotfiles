# Dotfiles Project

## Who I Am

Senior backend engineer. Primary stack: Java 25+, Spring Boot 4.x, Gradle, PostgreSQL, Kubernetes, Terraform. Also invests in Indian stock market (stocks and mutual funds). Lifelong learner. This is a personal macOS laptop.

## About This Repo

Personal dotfiles managing my macOS development environment. Forked originally from nicknisi/dotfiles, now fully customized and independent with clean git history.

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

### Brewfile
- Organized by category with comments: macOS, core, shell, dev tools, infra
- `cask` entries go inside `if OS.mac?` block
- Every entry needs a trailing comment explaining what it is
- No deprecated taps (homebrew/bundle is built-in now)

### Zsh Config
- `.zshrc` is sectioned with `########` comment blocks
- Profiler hooks wrap the entire file (start at top, stop at bottom)
- Homebrew completions before compinit
- compinit with 24h caching
- Tool initializations check `command -v` before running
- SDKMAN must be at the end (it modifies PATH)
- Starship init is the very last thing

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
