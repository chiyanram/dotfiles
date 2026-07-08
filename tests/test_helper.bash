# shellcheck shell=bash
# Shared helpers for dot-manager sandbox tests (core bats only — no external libs).
# BATS_TEST_DIRNAME and other BATS_* vars are injected by the bats runtime.
# shellcheck disable=SC2154

# Build an isolated sandbox: a fake HOME plus a minimal fixture DOTFILES that
# carries the real dot + common.sh so the manager runs exactly as in production.
setup_sandbox() {
  local repo_root
  repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"

  SANDBOX="$(mktemp -d)"
  export SANDBOX
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state" # isolate dot's state (manifests) to the sandbox
  export DOTFILES="$SANDBOX/dotfiles"
  export DOT="$DOTFILES/bin/dot"
  export TERM=dumb # no tty in CI; keeps tput/colors quiet

  mkdir -p "$HOME" "$XDG_CONFIG_HOME" \
    "$DOTFILES/bin/lib" "$DOTFILES/config/demo" "$DOTFILES/home"

  cp "$repo_root/bin/dot" "$DOTFILES/bin/dot"
  cp "$repo_root/bin/lib/common.sh" "$DOTFILES/bin/lib/common.sh"
  cp "$repo_root/bin/lib/profile.sh" "$DOTFILES/bin/lib/profile.sh"
  cp "$repo_root/bin/lib/brew.sh" "$DOTFILES/bin/lib/brew.sh"
  cp "$repo_root/bin/lib/links.sh" "$DOTFILES/bin/lib/links.sh"
  cp "$repo_root/bin/lib/sdkman.sh" "$DOTFILES/bin/lib/sdkman.sh"
  cp "$repo_root/bin/lib/reconcile.sh" "$DOTFILES/bin/lib/reconcile.sh"
  printf 'demo config\n' >"$DOTFILES/config/demo/demo.conf"
  printf 'demo home rc\n' >"$DOTFILES/home/.demorc"
}

teardown_sandbox() {
  [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"
}
