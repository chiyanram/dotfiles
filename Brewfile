# vim:ft=ruby

tap 'hashicorp/tap'

if OS.mac?
  # macOS utilities
  brew 'noti'                          # utility to display notifications from scripts
  brew 'trash'                         # rm, but put in the trash rather than completely delete

  # Applications
  cask 'ghostty'                       # a better terminal emulator
  cask 'nikitabobko/tap/aerospace'     # a tiling window manager
  cask 'docker-desktop'                 # Docker Desktop

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
brew 'tree'                            # pretty-print directory contents

# Development tools
brew 'neovim'                          # A better vim
brew 'tmux'                            # terminal multiplexer
brew 'sesh'                            # terminal session manager
brew 'lazygit'                         # a better git UI
brew 'gh'                              # GitHub CLI
brew 'git-delta'                       # a better git diff
brew 'entr'                            # file watcher / command runner
brew 'fnm'                             # Fast Node version manager
brew 'python'                          # python (latest)
brew 'stylua'                          # lua code formatter
brew 'shellcheck'                      # diagnostics for shell scripts
brew 'gum'                             # fancy UI utilities
brew 'glow'                            # markdown viewer
brew 'jq'                              # work with JSON files in shell scripts
brew 'gnupg'                           # GPG
brew 'btop'                            # a top alternative
brew 'wget'                            # internet file retriever

# Infrastructure & backend
brew 'kubectl'                         # Kubernetes CLI
brew 'helm'                            # Kubernetes package manager
brew 'k9s'                             # Kubernetes TUI
brew 'hashicorp/tap/terraform'         # Infrastructure as Code
brew 'httpie'                          # better HTTP client
brew 'pgcli'                           # PostgreSQL CLI with autocomplete
brew 'dive'                            # Docker image layer analyzer
