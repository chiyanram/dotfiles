# Dotfiles

Personal configuration files for my development environment on macOS. These dotfiles are tailored for backend engineering (Java/Spring Boot, Kubernetes, Terraform) with a focus on productivity and clean tooling.

## Fresh Laptop Setup

Step-by-step guide for setting up a brand new macOS machine.

### 1. Install XCode CLI tools

```bash
xcode-select --install
```

### 2. Clone this repo

Clone anywhere on your system. The dotfiles are location-independent.

```bash
git clone git@github.com:<your-username>/dotfiles.git
cd dotfiles
```

### 3. Install Homebrew

```bash
bin/dot homebrew install
```

### 4. Install packages from Brewfile

```bash
bin/dot homebrew bundle
```

### 5. Backup existing configs and link everything

```bash
bin/dot backup -v
bin/dot link all -v
```

### 6. Change default shell to ZSH

```bash
bin/dot shell change
```

### 7. Configure git identity

```bash
bin/dot git setup
```

### 8. Apply macOS defaults

```bash
bin/dot macos defaults
```

### 9. Install JVM tools

```bash
sdk install java
sdk install gradle
```

### 10. Verify everything

Open a new terminal, then:

```bash
dot doctor
```

> **Note:** After step 5 and opening a new shell, `dot` will be in your `$PATH` so you can drop the `bin/` prefix.

### Local Customization (not committed)

These files are sourced automatically if they exist:

| File | Purpose |
|------|---------|
| `~/.gitconfig-local` | Git name, email, signing key |
| `~/.localrc` | Machine-specific shell config |
| `~/.zshrc.local` | Additional shell config |
| `~/.zshenv.local` | Machine-specific env vars |

## The `dot` Command

The main entry point for managing dotfiles. All management happens through this single command.

### Basic Usage

```bash
dot help                    # Show help message and available commands
dot backup                  # Backup existing dotfiles
dot link [package]          # Link all or specific package
dot unlink [package]        # Unlink all or specific package
```

> **Important:** This command won't be in `$PATH` until ZSH is configured.
> Until then, run from the repo root:
> ```bash
> bin/dot <command> <subcommand>
> ```

### Built-in Commands

| Command | Description |
|---------|-------------|
| `dot link all` | Symlink all config packages to `~/.config` |
| `dot link <pkg>` | Link a specific package (e.g., `dot link nvim`) |
| `dot unlink all` | Remove all symlinks |
| `dot backup` | Create timestamped backup of existing dotfiles |
| `dot clean` | Remove broken legacy symlinks |
| `dot help` | Show all available commands |

### External Commands

| Command | Description |
|---------|-------------|
| `dot update all` | Update everything (Neovim, Homebrew, ZSH plugins, SDKMAN, dotfiles) |
| `dot update brew` | Update Homebrew packages |
| `dot update nvim` | Update Neovim plugins |
| `dot update zsh` | Update ZSH plugins |
| `dot update sdkman` | Update SDKMAN and installed SDKs |
| `dot update dotfiles` | Pull latest dotfiles from git |
| `dot doctor` | Health check — verify all required tools are installed |
| `dot git setup` | Configure git user settings interactively |
| `dot macos defaults` | Configure recommended macOS system defaults |
| `dot shell change` | Change default shell to zsh |
| `dot homebrew install` | Install Homebrew |
| `dot homebrew bundle` | Install packages from Brewfile |

### Extending with Custom Commands

Add executable scripts named `dot-<command>` anywhere in `$PATH`:

1. Create the script with a `# Description:` comment for help text
2. Make it executable
3. It becomes available as `dot <command>`

## What's Included

### Config Packages

Managed via `dot link`. Each directory in `config/` becomes a symlink in `~/.config/`.

| Package | Description |
|---------|-------------|
| `aerospace` | Tiling window manager for macOS |
| `ghostty` | Terminal emulator (Catppuccin theme) |
| `git` | Git configuration and global ignore |
| `lazygit` | Git TUI |
| `nvim` | Neovim (Lua config, lazy.nvim plugin manager) |
| `ripgrep` | Ripgrep configuration |
| `sesh` | Terminal session manager |
| `starship` | Cross-shell prompt (Java/K8s/Docker aware) |
| `tmux` | Terminal multiplexer |
| `zsh` | Shell configuration, aliases, functions, prompt |

### Shell (ZSH)

Configuration lives in `config/zsh/` and includes:

- **Starship prompt** with git status, Java version, K8s context, Docker status
- **Plugins** via `zfetch` (custom plugin manager):
  - zsh-async, zsh-syntax-highlighting, zsh-autosuggestions, fzf-tab, zsh-npm-scripts-autocomplete
- **Tool initialization**: fnm, pyenv, pnpm, zoxide, fzf, SDKMAN, starship
- **Docker aliases** (`config/zsh/.docker_aliases`)
- **Custom functions**: `c` (cd to workspaces), `g` (git shortcut), `md` (mkdir + cd)

### Neovim

Lua-based configuration at `config/nvim/`. Plugins managed by [lazy.nvim](https://github.com/folke/lazy.nvim).

```bash
# Headless plugin sync
vimu
```

### tmux

Custom keybindings with `⌃-a` prefix (remapped from `⌃-b`). Session management via `tm` command.

| Key | Action |
|-----|--------|
| `h/j/k/l` | Navigate panes |
| `H/J/K/L` | Resize panes |
| `-` | Vertical split |
| `\|` | Horizontal split |

Set `TMUX_MINIMAL=1` in `~/.localrc` to auto-hide the status bar with a single window.

## Development Tooling

### Java / Backend (via SDKMAN)

SDKMAN is initialized in `.zshrc` and manages Java, Gradle, Maven, and other JVM tools.

```bash
sdk install java            # Install latest Java
sdk install gradle          # Install Gradle
sdk list java               # List available Java versions
dot update sdkman           # Update SDKMAN and all installed SDKs
```

### Infrastructure (via Homebrew)

The Brewfile includes backend and infrastructure tools:

```bash
dot homebrew bundle         # Install everything from Brewfile
```

Installed tools include: `kubectl`, `helm`, `k9s`, `terraform`, `docker`, `httpie`, `pgcli`, `dive`

### Health Check

Verify your setup is complete:

```bash
dot doctor                  # Check all required and optional tools
```

## Homebrew Packages

Full list in `Brewfile`. Key packages:

| Category | Tools |
|----------|-------|
| Core | git, zsh, neovim, tmux |
| Shell | starship, fzf, fd, ripgrep, zoxide, bat, eza |
| Dev | lazygit, gh, git-delta, fnm, python, jq, shellcheck |
| Infra | kubectl, helm, k9s, terraform, docker, httpie, pgcli, dive |
| macOS | ghostty, aerospace, 1password-cli, trash, noti |

## macOS Settings

```bash
dot macos defaults
```

Configures: Finder (show extensions, hidden files, path bar), keyboard (fast repeat, full access), Terminal (UTF-8), and more.

## Docker Setup

A Dockerfile is included for testing linux support:

```bash
docker build -t dotfiles --force-rm .
docker run -it --rm dotfiles
```

## Preferred Software

- [Ghostty](https://ghostty.org) — GPU-accelerated terminal emulator
- [Aerospace](https://github.com/nikitabobko/AeroSpace) — i3-like tiling window manager for macOS
- [Neovim](https://neovim.io) — Editor
- [Starship](https://starship.rs) — Cross-shell prompt
- [Raycast](https://raycast.com) — Launcher
