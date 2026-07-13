# Regression for the worktree-safety bug (issue #142): running this repo's own
# `bin/dot` from inside a worktree must operate on the worktree's own files, even
# when an ambient DOTFILES (as `.zshenv` sets on every interactive shell) and PATH
# point at a different checkout entirely. Two bugs combined to break this:
#   1. bin/dot's own dispatch preferred a same-named command on PATH over the
#      copy living alongside itself.
#   2. Every dot-* script's own DOTFILES resolution honored an inherited
#      DOTFILES env var instead of always self-locating.
# This test builds two minimal checkouts and reproduces the exact real-world
# shape: PATH and DOTFILES both point at "main", but the worktree's own bin/dot
# is invoked directly by path — and must report on the worktree's own Brewfile.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks (e.g. /var -> /private/var)
  export TERM=dumb

  _build_checkout() {
    local dir="$1" declared="$2"
    mkdir -p "$dir/bin/lib" "$dir/brew"
    cp "$REPO/bin/dot" "$dir/bin/dot"
    cp "$REPO/bin/dot-reconcile" "$dir/bin/dot-reconcile"
    cp "$REPO/bin/lib/common.sh" "$dir/bin/lib/common.sh"
    cp "$REPO/bin/lib/profile.sh" "$dir/bin/lib/profile.sh"
    cp "$REPO/bin/lib/brew.sh" "$dir/bin/lib/brew.sh"
    cp "$REPO/bin/lib/links.sh" "$dir/bin/lib/links.sh"
    cp "$REPO/bin/lib/sdkman.sh" "$dir/bin/lib/sdkman.sh"
    cp "$REPO/bin/lib/reconcile.sh" "$dir/bin/lib/reconcile.sh"
    printf "%s\n" "$declared" >"$dir/brew/Brewfile.core"
  }

  # "main" declares shared-pkg (as if it had already been adopted there); the
  # "worktree" copy does NOT — the divergence the test tells apart.
  _build_checkout "$SANDBOX/main" "brew 'shared-pkg'"
  _build_checkout "$SANDBOX/worktree" "brew 'git'"

  # A fake brew reporting shared-pkg as installed, so it's undeclared ONLY
  # against the worktree's own Brewfile.core, not main's.
  mkdir -p "$SANDBOX/fakebin"
  cat >"$SANDBOX/fakebin/brew" <<'EOF'
#!/bin/bash
case "$1 ${2:-}" in
  "leaves ") printf '%s\n' shared-pkg ;;
  "list --formula") printf '%s\n' shared-pkg ;;
  "list --cask") : ;;
esac
EOF
  chmod +x "$SANDBOX/fakebin/brew"

  # Ambient state exactly like an interactive shell: DOTFILES + PATH point at
  # "main" (as .zshenv/.zshrc would), simulating the real-world bug scenario.
  export HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/home/.config"
  export DOTFILES="$SANDBOX/main"
  export PATH="$SANDBOX/main/bin:$SANDBOX/fakebin:/usr/bin:/bin"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "dot reconcile brew, run from a worktree's own bin/dot, reports against the worktree's Brewfile, not an ambient DOTFILES/PATH checkout" {
  run "$SANDBOX/worktree/bin/dot" reconcile brew
  [ "$status" -eq 0 ]
  [[ "$output" == *"shared-pkg"* ]]
}

@test "dot-reconcile invoked directly by its own worktree path ignores an ambient DOTFILES" {
  run "$SANDBOX/worktree/bin/dot-reconcile" brew
  [ "$status" -eq 0 ]
  [[ "$output" == *"shared-pkg"* ]]
}
