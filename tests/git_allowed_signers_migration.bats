setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks so include paths match
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  unset XDG_STATE_HOME # force the code's $HOME/.local/state fallback, not the real machine's
  export DOTFILES="$REPO"
  export TERM=dumb
  # Make git use a clean global config (the committed one) under XDG.
  export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
  mkdir -p "$XDG_CONFIG_HOME/git"
  cp "$REPO/config/git/config" "$GIT_CONFIG_GLOBAL"
  # Personal identity is the unconditional fallback (applies everywhere by default).
  git config -f "$HOME/.gitconfig-local" user.email "me@home.test"
  git config -f "$HOME/.gitconfig-local" user.name "Me Personal"
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -C "seed@test" -f "$HOME/seedkey" >/dev/null 2>&1
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "a pre-existing old-path allowed_signers is migrated to the new XDG state path with no data loss" {
  # Simulate a machine still on the old ~/.config/git/allowed_signers layout,
  # with a real, live signer entry that must survive the migration untouched.
  mkdir -p "$HOME/.config/git"
  printf 'someone@old.test ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOldEntryPlaceholder\n' \
    >"$HOME/.config/git/allowed_signers"

  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  # New path exists, is auto-migrated under $XDG_STATE_HOME (defaulted to
  # ~/.local/state since the sandbox does not export XDG_STATE_HOME), and
  # contains BOTH the pre-existing entry and the newly added slot's entry.
  local new_path="$HOME/.local/state/dot/git/allowed_signers"
  [ -f "$new_path" ]
  run cat "$new_path"
  [[ "$output" == *"someone@old.test ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOldEntryPlaceholder"* ]]
  [[ "$output" == *"me@work.test ssh-ed25519 "* ]]

  # Old path is no longer used going forward: the file was moved, not copied.
  [ ! -f "$HOME/.config/git/allowed_signers" ]
}

@test "with no pre-existing file at either path, add-identity creates only the new path" {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --key "$HOME/seedkey"

  [ -f "$HOME/.local/state/dot/git/allowed_signers" ]
  [ ! -f "$HOME/.config/git/allowed_signers" ]
}
