#!/usr/bin/env bash
# Bootstrap dotfiles on a bare macOS machine.
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/chiyanram/dotfiles/main/bootstrap.sh)

set -Eeuo pipefail

DOTFILES_REPO="https://github.com/chiyanram/dotfiles.git"
DOTFILES_DIR="${DOTFILES:-$HOME/tools-repo/dotfiles}"

echo "==> Checking for Xcode Command Line Tools..."
if xcode-select -p &>/dev/null; then
  echo "    Already installed"
else
  echo "==> Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "==> Waiting for installation to complete..."
  until xcode-select -p &>/dev/null; do
    sleep 5
  done
  echo "    Installed"
fi

echo "==> Cloning dotfiles..."
if [[ -d "$DOTFILES_DIR/.git" ]]; then
  echo "    Already cloned at $DOTFILES_DIR"
else
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  echo "    Cloned to $DOTFILES_DIR"
fi

echo "==> Running setup..."
exec "$DOTFILES_DIR/setup.sh"
