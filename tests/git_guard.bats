setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks so include paths match
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export DOTFILES="$REPO"
  export TERM=dumb
  # Make git use a clean global config (the committed one) under XDG.
  export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
  mkdir -p "$XDG_CONFIG_HOME/git"
  cp "$REPO/config/git/config" "$GIT_CONFIG_GLOBAL"
  # Personal identity is the unconditional fallback (applies everywhere by default).
  git config -f "$HOME/.gitconfig-local" user.email "me@home.test"
  git config -f "$HOME/.gitconfig-local" user.name "Me Personal"
  # Pre-generate a throwaway passphrase-less key so tests never hit an interactive prompt.
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -C "seed@test" -f "$HOME/seedkey" >/dev/null 2>&1

  HOOK="$REPO/config/git/hooks/pre-commit"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Create an ee slot (github.com) with the passphrase-less seed key.
_add_ee_slot() {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --github-user workuser --key "$HOME/seedkey" >/dev/null
}

# Install the guard: point core.hooksPath (in ~/.gitconfig-local) at the committed hook dir.
_install_guard() { "$REPO/bin/dot-git" install-guard >/dev/null; }

# mkrepo <dir> <origin-url> — init a repo and set its origin.
_mkrepo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" remote add origin "$2"
}

# Stage a trivial change so `git commit` actually reaches the pre-commit hook.
_stage() {
  echo change >"$1/file"
  git -C "$1" add file
}

# Run with a wall-clock bound when a timeout tool exists (macOS CI ships neither,
# so it degrades to a plain run — the guard is correct-by-construction there).
_bounded() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$@"
  else
    shift
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Delegation (written first, red before the hook delegates).
# ---------------------------------------------------------------------------

@test "delegates to a repo-local pre-commit hook and honors its success (proves it runs)" {
  _install_guard
  mkdir -p "$HOME/proj"
  git -C "$HOME/proj" init -q # no origin -> identity check passes, delegation reached
  cat >"$HOME/proj/.git/hooks/pre-commit" <<EOF
#!/usr/bin/env bash
touch "$HOME/proj/LOCAL_HOOK_RAN"
exit 0
EOF
  chmod +x "$HOME/proj/.git/hooks/pre-commit"
  _stage "$HOME/proj"

  cd "$HOME/proj"
  run git commit --no-gpg-sign -m x
  [ "$status" -eq 0 ]
  # The marker only exists if the guard explicitly delegated to .git/hooks/pre-commit
  # (core.hooksPath otherwise shadows it entirely).
  [ -f "$HOME/proj/LOCAL_HOOK_RAN" ]
}

@test "propagates a repo-local pre-commit hook's failure (blocks the commit)" {
  _install_guard
  mkdir -p "$HOME/proj"
  git -C "$HOME/proj" init -q # no origin -> identity passes; only the local hook can block
  cat >"$HOME/proj/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "local hook vetoes this commit" >&2
exit 1
EOF
  chmod +x "$HOME/proj/.git/hooks/pre-commit"
  _stage "$HOME/proj"

  cd "$HOME/proj"
  run git commit --no-gpg-sign -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"local hook vetoes this commit"* ]]
}

# ---------------------------------------------------------------------------
# Block.
# ---------------------------------------------------------------------------

@test "blocks a commit whose origin is a known forge with no matching slot" {
  _install_guard
  _mkrepo "$HOME/proj" "git@github.com:owner/repo.git"
  _stage "$HOME/proj"

  cd "$HOME/proj"
  run git commit --no-gpg-sign -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"github.com"* ]]
  # No slot exists for the host -> the remedy is add-identity.
  [[ "$output" == *"add-identity"* ]]
}

@test "blocks with a 'dot git use <slot>' remedy when a slot exists for the host" {
  _add_ee_slot
  _install_guard
  _mkrepo "$HOME/proj" "git@github.com:owner/repo.git" # plain URL, not the alias
  _stage "$HOME/proj"

  cd "$HOME/proj"
  run git commit --no-gpg-sign -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"dot git use ee"* ]]
}

# ---------------------------------------------------------------------------
# Allow.
# ---------------------------------------------------------------------------

@test "allows a commit in a repo with no origin remote (scratch)" {
  _install_guard
  mkdir -p "$HOME/scratch"
  git -C "$HOME/scratch" init -q
  _stage "$HOME/scratch"

  cd "$HOME/scratch"
  run git commit --no-gpg-sign -m x
  [ "$status" -eq 0 ]
}

@test "allows a commit when origin is already on a valid slot alias" {
  _add_ee_slot
  _install_guard
  _mkrepo "$HOME/proj" "git@github.com-ee:owner/repo.git"
  _stage "$HOME/proj"

  cd "$HOME/proj"
  run git commit --no-gpg-sign -m x
  [ "$status" -eq 0 ]
}

@test "allows a commit for an unknown non-forge host with no slot" {
  _install_guard
  _mkrepo "$HOME/proj" "git@git.internal.example:owner/repo.git"
  _stage "$HOME/proj"

  cd "$HOME/proj"
  run git commit --no-gpg-sign -m x
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Recursion.
# ---------------------------------------------------------------------------

@test "does not loop when core.hooksPath points at the guard and there is no local hook" {
  _install_guard
  mkdir -p "$HOME/proj"
  git -C "$HOME/proj" init -q # no origin, no local hook
  _stage "$HOME/proj"

  cd "$HOME/proj"
  run _bounded 20 git commit --no-gpg-sign -m x
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Install wiring.
# ---------------------------------------------------------------------------

@test "install-guard writes core.hooksPath to ~/.gitconfig-local, not the committed config" {
  _install_guard
  run git config -f "$HOME/.gitconfig-local" core.hooksPath
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO/config/git/hooks" ]
  # The committed shared config must never carry the machine-specific absolute path.
  run grep -q "hooksPath" "$REPO/config/git/config"
  [ "$status" -ne 0 ]
}
