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

# ── Step 3: SSH key ────────────────────────────────────────────────

run_step "SSH key"

if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
  log_success "SSH key already exists (~/.ssh/id_ed25519)"
else
  if ask_yes_no "Generate a new SSH key?"; then
    printf "Email for SSH key: "
    read -r ssh_email

    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$ssh_email" -f "$HOME/.ssh/id_ed25519"
    eval "$(ssh-agent -s)" >/dev/null
    ssh-add "$HOME/.ssh/id_ed25519"

    log_success "SSH key generated"
    echo
    log_info "Add this public key to GitHub → Settings → SSH Keys:"
    echo
    cat "$HOME/.ssh/id_ed25519.pub"
    echo
    if command -v pbcopy &>/dev/null; then
      pbcopy < "$HOME/.ssh/id_ed25519.pub"
      log_info "Public key copied to clipboard"
    fi

    log_warning "Press any key after adding the key to GitHub"
    read -r -n 1 -s
  else
    log_info "Skipping — generate later: ssh-keygen -t ed25519"
  fi
fi

# ── Step 4: Docker runtime ──────────────────────────────────────────

run_step "Docker runtime"

if brew list --cask docker-desktop &>/dev/null; then
  log_success "Docker Desktop already installed"
  export HOMEBREW_DOCKER_RUNTIME="docker-desktop"
elif brew list --cask rancher &>/dev/null; then
  log_success "Rancher Desktop already installed"
  export HOMEBREW_DOCKER_RUNTIME="rancher"
else
  echo "  1) Docker Desktop (default — personal laptop)"
  echo "  2) Rancher Desktop (company laptop)"
  echo
  printf "Choose [1/2]: "
  read -r docker_choice

  case "$docker_choice" in
    2)
      export HOMEBREW_DOCKER_RUNTIME="rancher"
      log_info "Using Rancher Desktop"
      ;;
    *)
      export HOMEBREW_DOCKER_RUNTIME="docker-desktop"
      log_info "Using Docker Desktop"
      ;;
  esac
fi

# ── Step 5: Brew bundle ─────────────────────────────────────────────

run_step "Install Homebrew packages"

"$DOT" homebrew bundle

# ── Step 6: Backup & link ───────────────────────────────────────────

run_step "Backup existing configs & link dotfiles"

"$DOT" backup -v || true
"$DOT" link all -v

# ── Step 7: Default shell ───────────────────────────────────────────

run_step "Change default shell to ZSH"

"$DOT" shell change

# ── Step 8: Git identity ──────────────────────────────────────────

run_step "Configure git identity"

if [[ -f "$HOME/.gitconfig-local" ]]; then
  log_success "Git identity already configured (~/.gitconfig-local)"
else
  "$DOT" git setup
fi

# ── Step 9: macOS defaults ─────────────────────────────────────────

run_step "macOS system defaults"

if ask_yes_no "Apply recommended macOS defaults?"; then
  "$DOT" macos defaults
else
  log_info "Skipping — run 'dot macos defaults' later"
fi

# ── Step 10: SDKMAN & JVM tools ────────────────────────────────────

run_step "SDKMAN & JVM tools"

if [[ -d "$HOME/.sdkman" ]]; then
  log_success "SDKMAN already installed"
else
  if ask_yes_no "Install SDKMAN (Java, Gradle, Maven manager)?"; then
    log_info "Installing SDKMAN..."
    curl -s "https://get.sdkman.io" | bash
    export SDKMAN_DIR="$HOME/.sdkman"
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
    log_success "SDKMAN installed"

    if ask_yes_no "Install latest Java?"; then
      sdk install java
    fi
    if ask_yes_no "Install latest Gradle?"; then
      sdk install gradle
    fi
  else
    log_info "Skipping — install later: curl -s https://get.sdkman.io | bash"
  fi
fi

# ── Step 11: Health check ──────────────────────────────────────────

run_step "Health check"

"$DOT" doctor

# ── Done ────────────────────────────────────────────────────────────

echo
fmt_title_border "Setup complete!"
echo
log_info "Open a new terminal for all changes to take effect"
log_info "Run 'dot doctor' anytime to verify your setup"

if [[ "${HOMEBREW_DOCKER_RUNTIME:-}" == "rancher" ]]; then
  log_info "Company laptop: add 'export HOMEBREW_DOCKER_RUNTIME=rancher' to ~/.localrc"
fi
