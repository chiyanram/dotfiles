# vim:ft=ruby

if OS.mac?
  # macOS utilities
  brew 'noti'                          # utility to display notifications from scripts
  brew 'trash'                         # rm, but put in the trash rather than completely delete

  # Applications
  cask 'ghostty'                       # a better terminal emulator
  cask 'nikitabobko/tap/aerospace'     # a tiling window manager
  cask ENV.fetch('HOMEBREW_DOCKER_RUNTIME', 'docker-desktop')  # Docker runtime (set HOMEBREW_DOCKER_RUNTIME=rancher for Rancher Desktop)

  # Fonts
  cask 'font-symbols-only-nerd-font'   # nerd-only symbols font
elsif OS.linux?
  brew 'xclip'                         # access to clipboard (similar to pbcopy/pbpaste)
end

# Latest versions of some core utilities
brew 'git'                             # Git version control
brew 'bash'                            # bash shell
brew 'zsh'                             # zsh shell
brew 'grep'                            # grep

# Shell & navigation
brew 'starship'                        # cross-shell prompt
brew 'fzf'                             # Fuzzy file searcher, used in scripts and in vim
brew 'fd'                              # find alternative
brew 'ripgrep'                         # very fast file searcher
brew 'zoxide'                          # switch between most used directories
brew 'bat'                             # better cat
brew 'eza'                             # ls alternative
brew 'procs'                           # modern ps with color and tree view

# Development tools
brew 'neovim'                          # A better vim
brew 'tmux'                            # terminal multiplexer
brew 'sesh'                            # terminal session manager
brew 'lazygit'                         # a better git UI
brew 'gh'                              # GitHub CLI
brew 'git-delta'                       # a better git diff
brew 'entr'                            # file watcher / command runner
brew 'just'                            # project command runner (like make, but better)
brew 'direnv'                          # per-directory environment variables via .envrc
brew 'fnm'                             # Fast Node version manager
brew 'python'                          # python (latest)
brew 'stylua'                          # lua code formatter
brew 'shellcheck'                      # diagnostics for shell scripts
brew 'glow'                            # terminal markdown viewer
brew 'jq'                              # work with JSON files in shell scripts
brew 'gnupg'                           # GPG
brew 'btop'                            # a top alternative

# Java / backend
brew 'jbang'                           # run Java source files as scripts without a project

# Infrastructure
brew 'yq'                              # jq for YAML — essential for K8s/Helm work
brew 'kubectl'                         # Kubernetes CLI
brew 'kubecolor'                       # colorized kubectl output
brew 'helm'                            # Kubernetes package manager
brew 'k9s'                             # Kubernetes TUI
brew 'kubectx'                         # fast Kubernetes context and namespace switching
brew 'stern'                           # multi-pod log tailing for Kubernetes
brew 'httpie'                          # better HTTP client
brew 'pgcli'                           # PostgreSQL CLI with autocomplete
brew 'dive'                            # Docker image layer analyzer
brew 'lazydocker'                      # Docker TUI (containers, images, volumes, logs)
