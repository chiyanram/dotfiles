# Dotfiles

Personal configuration files for my development environment on macOS. These dotfiles are tailored for backend engineering (Java/Spring Boot, Kubernetes, Terraform) with a focus on productivity and clean tooling.

## Fresh Laptop Setup

Clone the repo and run the interactive setup script:

```bash
xcode-select --install        # if not already installed
git clone git@github.com:<your-username>/dotfiles.git
cd dotfiles
./setup.sh
```

The script walks you through each step interactively:

1. Xcode CLI tools check
2. Homebrew installation
3. SSH key generation (copies public key to clipboard)
4. Docker runtime selection (Docker Desktop or Rancher Desktop)
5. Homebrew package installation
6. Backup existing configs and symlink dotfiles
7. Set ZSH as default shell
8. Git identity configuration
9. macOS system defaults (optional, can skip)
10. SDKMAN + Java/Gradle installation (optional, can skip)
11. Health check via `dot doctor`

> **Note:** After setup, open a new terminal. `dot` will be in your `$PATH`.

### Docker Runtime

The Brewfile defaults to Docker Desktop. For company laptops that require Rancher Desktop:

```bash
# Add to ~/.localrc so future brew bundle runs use Rancher
export HOMEBREW_DOCKER_RUNTIME=rancher
```

The setup script asks which runtime to use during installation.

### Manual Setup

If you prefer to run steps individually:

```bash
bin/dot homebrew install        # Install Homebrew
bin/dot homebrew bundle         # Install Brewfile packages
bin/dot backup -v               # Backup existing configs
bin/dot link all -v             # Symlink all packages
bin/dot shell change            # Set ZSH as default shell
bin/dot git setup               # Configure git identity
bin/dot macos defaults          # Apply macOS defaults
dot doctor                      # Verify everything
```

### Local Customization (not committed)

These files are sourced automatically if they exist:

| File | Purpose |
|------|---------|
| `~/.gitconfig-local` | Git name, email, signing key |
| `~/.localrc` | Machine-specific shell config (e.g., `HOMEBREW_DOCKER_RUNTIME`) |
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
| `docker` | Docker completions |
| `ghostty` | Terminal emulator (Catppuccin theme) |
| `git` | Git configuration and global ignore |
| `lazygit` | Git TUI |
| `nvim` | Neovim (Lua config, lazy.nvim plugin manager) |
| `ripgrep` | Ripgrep configuration |
| `sesh` | Terminal session manager |
| `starship` | Cross-shell prompt (Java/K8s/Docker aware) |
| `tmux` | Terminal multiplexer |
| `zsh` | Shell configuration, aliases, functions |

### Shell (ZSH)

Configuration lives in `config/zsh/` and includes:

- **Starship prompt** with git status, Java version, K8s context, Docker status
- **Plugins** via `zfetch` (custom plugin manager):
  - zsh-completions, zsh-syntax-highlighting, zsh-autosuggestions, zsh-history-substring-search, zsh-you-should-use, zsh-npm-scripts-autocomplete, fzf-tab, fzf-git.sh
- **Tool initialization**: fnm, pyenv, pnpm, zoxide, direnv, fzf, SDKMAN, starship
- **Docker aliases** (`config/zsh/.docker_aliases`)
- **Custom functions**: `c` (cd to workspaces), `h` (cd to home subdir), `g` (git shortcut), `md` (mkdir + cd), `zfetch` (plugin manager)

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

Installed tools include: `kubectl`, `helm`, `k9s`, `kubectx`, `stern`, `docker`, `lazydocker`, `httpie`, `pgcli`, `dive`

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
| Shell | starship, fzf, fd, ripgrep, zoxide, bat, eza, sd, dust, procs |
| Dev | lazygit, gh, git-delta, just, direnv, fnm, python, jq, jnv, shellcheck |
| Java | jbang, sdkman (external) |
| Infra | kubectl, helm, k9s, kubectx, stern, docker, lazydocker, httpie, pgcli, dive |
| macOS | ghostty, aerospace, trash, noti |

## macOS Settings

```bash
dot macos defaults
```

Configures: Finder (show extensions, hidden files, path bar), keyboard (fast repeat, full access), Terminal (UTF-8), and more.

## Preferred Software

- [Ghostty](https://ghostty.org) — GPU-accelerated terminal emulator
- [Aerospace](https://github.com/nikitabobko/AeroSpace) — i3-like tiling window manager for macOS
- [Neovim](https://neovim.io) — Editor
- [Starship](https://starship.rs) — Cross-shell prompt
- [Raycast](https://raycast.com) — Launcher
