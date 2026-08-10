# shellcheck shell=bash
# Shared helpers for dot-manager sandbox tests (core bats only — no external libs).
# BATS_TEST_DIRNAME and other BATS_* vars are injected by the bats runtime.
# shellcheck disable=SC2154

# Build an isolated sandbox: a fake HOME plus a minimal fixture DOTFILES that
# carries the real dot + common.sh so the manager runs exactly as in production.
setup_sandbox() {
  local repo_root
  repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"

  # Pin pre-commit's store OUTSIDE the sandbox, resolved against the REAL $HOME
  # before the override below (#179). pre-commit defaults its store to
  # $XDG_CACHE_HOME/pre-commit, falling back to $HOME/.cache/pre-commit — and
  # with $HOME pointing into the sandbox, that fallback makes it clone repos and
  # build hook environments inside a temp dir we are about to delete. Two costs:
  # every sandboxed run reinstalls the whole store, and teardown's `rm -rf` races
  # the subprocesses still writing into it ("Directory not empty").
  #
  # Only bites where XDG_CACHE_HOME is unset, which is why this reproduced on CI
  # and never locally — a local shell exports it, so the real store got reused.
  if [ -z "${PRE_COMMIT_HOME:-}" ]; then
    PRE_COMMIT_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/pre-commit"
  fi
  export PRE_COMMIT_HOME

  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks (e.g. /var -> /private/var on
  # macOS) so this matches dot's own self-located, pwd -P-resolved DOTFILES exactly.
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
  if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
}
