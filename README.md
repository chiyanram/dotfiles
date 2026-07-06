# Dotfiles

Personal configuration files for my development environment on macOS. These dotfiles are tailored for backend engineering (Java/Spring Boot, Kubernetes, Terraform) with a focus on productivity and clean tooling.

## Quick Start (Bare Machine)

Open Terminal.app on a fresh Mac and paste:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/chiyanram/dotfiles/main/bootstrap.sh)
```

This handles everything: Xcode CLI tools, git clone, and the full interactive setup.

### Manual Setup

If you prefer to clone manually:

```bash
git clone git@github.com:chiyanram/dotfiles.git ~/tools-repo/dotfiles
cd ~/tools-repo/dotfiles
./setup.sh
```

The script prints and runs each step (any step it can't do is skipped, and the run always finishes with a summary):

1. Xcode CLI tools
2. Homebrew
3. Machine profile — `personal`/`work` (also picks the Docker runtime)
4. SSH key (+ trusts `github.com` so the first `git push` doesn't prompt)
5. Homebrew packages (`dot homebrew bundle`)
6. Backup existing configs & symlink dotfiles
7. Default shell → zsh
8. Git identity
9. macOS system defaults (optional)
10. JVM toolchain via SDKMAN (`dot sdkman install` — Temurin JDKs + gradle/maven/mvnd/kotlin)
11. Health check (`dot doctor`)

> **Note:** After setup, open a new terminal. `dot` will be in your `$PATH`.

### Migrating an Existing Laptop

Already have dotfiles installed? One command pulls latest changes, cleans stale symlinks, force-relinks configs, installs new packages, and runs a health check:

```bash
dot migrate
```

### Docker Runtime

The Docker runtime is profile-resolved: `personal` defaults to Docker Desktop, `work` defaults to Rancher Desktop. Override with:

```bash
dot profile set-config docker_runtime <docker-desktop|rancher|colima>
```

The setup script asks which runtime to use during installation.

### Running Steps Individually

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

| File                 | Purpose                                                         |
| -------------------- | --------------------------------------------------------------- |
| `~/.gitconfig-local` | Git name, email, signing key                                    |
| `~/.localrc`         | Machine-specific shell config (e.g., `HOMEBREW_DOCKER_RUNTIME`) |
| `~/.zshrc.local`     | Additional shell config                                         |
| `~/.zshenv.local`    | Machine-specific env vars                                       |

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
>
> ```bash
> bin/dot <command> <subcommand>
> ```

### Built-in Commands

| Command             | Description                                                        |
| ------------------- | ------------------------------------------------------------------ |
| `dot link all`      | Symlink every config/home package into place                       |
| `dot link <pkg>`    | Link a specific package (e.g., `dot link nvim`)                    |
| `dot link --status` | Show link health (OK/MISSING/WRONG/REAL); exits non-zero if broken |
| `dot restore`       | Undo the last `dot link` run (removes/repoints what it created)    |
| `dot unlink all`    | Remove all symlinks                                                |
| `dot backup`        | Timestamped backup of existing dotfiles                            |
| `dot clean`         | Remove broken/stale symlinks                                       |
| `dot help`          | List all commands (built-in + auto-discovered `dot-*`)             |

**Safe linking — preview, apply, undo.** `dot link` never blindly overwrites:

```bash
dot link all -n             # preview the plan (CREATE/SKIP/REPLACE/CONFLICT); non-zero on conflict
dot link all -n -v          # ...plus a diff of any conflicting file
dot link all                # apply (records a manifest under ~/.local/state/dot/)
dot restore                 # undo that run
```

When a real file sits where a link should go, `dot link` refuses by default; resolve it explicitly:

- `dot link all -b` — move the file to `<target>.backup.<ts>`, then link (restorable via `dot restore`)
- `dot link all --adopt` — import the live file into the repo, then link (git-recoverable)

### External Commands

`dot-*` scripts are auto-discovered from `$PATH`, so **`dot help` is the authoritative, always-current list** (any table here would only go stale). The main families:

- **`dot doctor`** — health check (config links, shell, plugins, tools, drift summary); `--strict` fails on any warning
- **`dot reconcile [domain]`** — read-only drift report vs the repo's declared state: installed-but-undeclared and declared-but-missing, per domain (brew, sdkman, plugins, symlinks)
- **`dot update <all|brew|nvim|zsh|sdkman|dotfiles>`** — update installed things (reports what actually _changed_)
- **`dot sdkman <install|plan|env>`** — the JVM toolchain (see [Java / Backend](#java--backend-sdkman))
- **`dot homebrew <install|bundle>`** — Homebrew itself + Brewfile packages
- **`dot profile <show|set|set-config>`** — personal/work profile + per-machine config
- **`dot migrate`** — pull latest, clean, relink, install, health check (for an already-set-up machine)
- **`dot git setup`**, **`dot macos defaults`**, **`dot shell change`** — one-off setup helpers

### Extending with Custom Commands

Add executable scripts named `dot-<command>` anywhere in `$PATH`:

1. Create the script with a `# Description:` comment for help text
2. Make it executable
3. It becomes available as `dot <command>`

## What's Included

### Config Packages

Managed via `dot link`. Each directory in `config/` becomes a symlink in `~/.config/`.

Each directory under `config/` is a package (the list below is a snapshot — `ls config/` is authoritative):

| Package    | Description                                                    |
| ---------- | -------------------------------------------------------------- |
| `atuin`    | Shell history database (Ctrl-R)                                |
| `ghostty`  | Terminal emulator (Catppuccin theme)                           |
| `git`      | Git configuration and global ignore                            |
| `lazygit`  | Git TUI                                                        |
| `mise`     | Node/Python runtime manager (reads `.nvmrc`/`.python-version`) |
| `nvim`     | Neovim (Lua config, lazy.nvim plugin manager)                  |
| `ripgrep`  | Ripgrep configuration                                          |
| `sesh`     | Terminal session manager                                       |
| `starship` | Cross-shell prompt (Java/K8s/Docker aware)                     |
| `tmux`     | Terminal multiplexer                                           |

Zsh rc files (`.zshrc`, `.zprofile`, `.zsh_aliases`, `.zsh_functions`, `.docker_aliases`) live under `home/` and symlink directly into `$HOME`.

### Shell (ZSH)

Configuration lives in `home/` (`.zshrc`, `.zsh_functions`, `.zsh_aliases`, `.zprofile`, `.docker_aliases`) and includes:

- **Starship prompt** with git status, Java version, K8s context, Docker status
- **Plugins** via `zfetch` (custom plugin manager):
  - zsh-completions, zsh-syntax-highlighting, zsh-autosuggestions, zsh-history-substring-search, zsh-you-should-use, fzf-tab, fzf-git.sh
- **Tool initialization**: mise (Node/Python), zoxide, direnv, fzf, atuin, SDKMAN (lazy-loaded), starship
- **Docker aliases** (`home/.docker_aliases`)
- **Custom functions**: `c` (cd to workspaces), `h` (cd to home subdir), `g` (git shortcut), `md` (mkdir + cd), `zfetch` (plugin manager)

### Neovim

Lua-based configuration at `config/nvim/`. Plugins managed by [lazy.nvim](https://github.com/folke/lazy.nvim).

```bash
# Headless plugin sync
vimu
```

### tmux

Custom keybindings with `⌃-a` prefix (remapped from `⌃-b`). Session management via `sesh` (the terminal session manager).

| Key       | Action           |
| --------- | ---------------- |
| `h/j/k/l` | Navigate panes   |
| `H/J/K/L` | Resize panes     |
| `-`       | Vertical split   |
| `\|`      | Horizontal split |

Set `TMUX_MINIMAL=1` in `~/.localrc` to auto-hide the status bar with a single window.

### Ghostty quick-terminal

A quake-style dropdown toggles from any app with `Ctrl`+`` ` ``. macOS requires a one-time
Accessibility grant for the global hotkey: **System Settings → Privacy & Security →
Accessibility → enable Ghostty.** If `Ctrl`+`` ` `` collides on a machine, override it in
`~/.config/ghostty/overrides` with `keybind = global:cmd+ctrl+grave=toggle_quick_terminal`.

## Development Tooling

### Java / Backend (SDKMAN)

The JVM toolchain is **declared** in `sdkman/toolchain` — the "Brewfile for SDKMAN" — and installed by `dot sdkman` (`setup.sh` runs `install` for you):

```bash
dot sdkman plan             # Show the resolved plan (which Temurin patch each major maps to)
dot sdkman install          # Install everything in sdkman/toolchain (idempotent)
dot sdkman env 21           # Pin java 21 in ./.sdkmanrc for this project (or: env latest)
dot update sdkman           # Upgrade SDKMAN + installed SDKs
```

`sdkman/toolchain` lists gradle/maven/mvnd/kotlin (latest stable) plus several Temurin JDKs (`java latest` + the LTS majors). The **global default JDK is the latest**; per-project JDKs are pinned in a `.sdkmanrc` that auto-switches on `cd`. `dot sdkman env <major>` resolves the exact `-tem` version for you — no manual lookup of version strings.

### Packages (Homebrew)

Packages are declared in `brew/Brewfile.core` (cross-profile) plus `brew/Brewfile.{personal,work}` (profile-specific) — **those files are the source of truth**; read them for the full, current list.

```bash
dot homebrew bundle         # Install everything for the active profile
```

Spans CLI tools (git, neovim, ripgrep, fzf, kubectl, helm, k9s, jq, git-delta, …), GUI casks (ghostty, intellij-idea, claude-code, jdk-mission-control), and profile-specific infra (the Docker runtime, dive, lazydocker).

Homebrew 6 refuses to load formulae/casks from untrusted third-party taps, which can abort the whole bundle even though the Brewfiles declare no taps (formula resolution may touch a machine-local tap). Before bundling, `dot homebrew bundle` therefore auto-trusts each untrusted tap that has packages installed from it, and warns about untrusted taps with nothing installed (trust them with `brew trust --tap <tap>` or remove them with `brew untap <tap>`). A fresh machine has no taps, so this is a no-op on day 0.

### Health Check

Verify your setup is complete:

```bash
dot doctor                  # Check all required and optional tools
```

## macOS Settings

```bash
dot macos defaults
```

Configures: Finder (show extensions, hidden files, path bar), keyboard (fast repeat, full access), Terminal (UTF-8), and more.

## Preferred Software

- [Ghostty](https://ghostty.org) — GPU-accelerated terminal emulator
- [Neovim](https://neovim.io) — Editor
- [Starship](https://starship.rs) — Cross-shell prompt
