#!/usr/bin/env bash

set -Eeuo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"
source "$DOTFILES/bin/lib/common.sh"

DOT="$DOTFILES/bin/dot"

step=0

run_step() {
  step=$((step + 1))
  echo
  fmt_title_underline "Step $step: $1"
}

ask_yes_no() {
  local prompt="$1"
  local answer
  printf "%b" "$prompt [y/N] "
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ── Step 1: Xcode CLI tools ────────────────────────────────────────

run_step "Xcode Command Line Tools"

if xcode-select -p &>/dev/null; then
  log_success "Xcode CLI tools already installed"
else
  log_info "Installing Xcode CLI tools..."
  xcode-select --install
  log_warning "Press any key after the installation finishes"
  read -r -n 1 -s
fi

# ── Step 2: Homebrew ────────────────────────────────────────────────

run_step "Homebrew"

if command -v brew &>/dev/null; then
  log_success "Homebrew already installed"
else
  "$DOT" homebrew install
fi

# ── Step 3: Docker runtime ──────────────────────────────────────────

run_step "Docker runtime"

echo "  1) Docker Desktop (default — personal laptop)"
echo "  2) Rancher Desktop (company laptop)"
echo
printf "Choose [1/2]: "
read -r docker_choice

case "$docker_choice" in
  2)
    export DOCKER_RUNTIME="rancher"
    log_info "Using Rancher Desktop"
    ;;
  *)
    export DOCKER_RUNTIME="docker-desktop"
    log_info "Using Docker Desktop"
    ;;
esac

# ── Step 4: Brew bundle ─────────────────────────────────────────────

run_step "Install Homebrew packages"

"$DOT" homebrew bundle

# ── Step 5: Backup & link ───────────────────────────────────────────

run_step "Backup existing configs & link dotfiles"

"$DOT" backup -v
"$DOT" link all -v

# ── Step 6: Default shell ───────────────────────────────────────────

run_step "Change default shell to ZSH"

"$DOT" shell change

# ── Step 7: Git identity ────────────────────────────────────────────

run_step "Configure git identity"

if ask_yes_no "Configure git user settings now?"; then
  "$DOT" git setup
else
  log_info "Skipping — run 'dot git setup' later"
fi

# ── Step 8: macOS defaults ──────────────────────────────────────────

run_step "macOS system defaults"

if ask_yes_no "Apply recommended macOS defaults?"; then
  "$DOT" macos defaults
else
  log_info "Skipping — run 'dot macos defaults' later"
fi

# ── Step 9: Health check ────────────────────────────────────────────

run_step "Health check"

"$DOT" doctor

# ── Done ────────────────────────────────────────────────────────────

echo
fmt_title_border "Setup complete!"
echo
log_info "Open a new terminal for all changes to take effect"
log_info "Run 'dot doctor' anytime to verify your setup"

if [[ "$DOCKER_RUNTIME" == "rancher" ]]; then
  log_info "Company laptop: add 'export DOCKER_RUNTIME=rancher' to ~/.localrc"
fi
