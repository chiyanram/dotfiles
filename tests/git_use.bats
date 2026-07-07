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

  # A fake `gh` on PATH that only records its args — so `use`'s account sync is
  # observable and the real gh (and its real auth state) is never touched.
  export GH_LOG="$HOME/gh.log"
  mkdir -p "$HOME/bin"
  cat >"$HOME/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$GH_LOG"
EOF
  chmod +x "$HOME/bin/gh"
  export PATH="$HOME/bin:$PATH"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Create an ee slot (github.com) with a passphrase-less seed key.
_add_ee_slot() {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --github-user workuser --key "$HOME/seedkey" >/dev/null
}

# mkrepo <dir> <origin-url> — init a repo and set its origin.
_mkrepo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" remote add origin "$2"
}

# Build a PATH whose bin dir has the tools `dot git use` needs but NO gh,
# so `command -v gh` fails without touching the real gh.
_nogh_path() {
  local dir="$HOME/nogh" t
  mkdir -p "$dir"
  for t in env bash sh basename dirname git awk grep sed cat mktemp rm mkdir touch chmod; do
    local p
    p="$(command -v "$t" 2>/dev/null || true)"
    [[ -n "$p" ]] && ln -sf "$p" "$dir/$t"
  done
  printf '%s\n' "$dir"
}

@test "use rewrites an HTTPS origin to the slot alias and binds the identity" {
  _add_ee_slot
  _mkrepo "$HOME/proj" "https://github.com/owner/repo.git"

  cd "$HOME/proj"
  run "$REPO/bin/dot-git" use ee
  [ "$status" -eq 0 ]

  run git -C "$HOME/proj" remote get-url origin
  [ "$output" = "git@github.com-ee:owner/repo.git" ]

  run git -C "$HOME/proj" config user.email
  [ "$output" = "me@work.test" ]
}

@test "use rewrites a scp-style origin to the slot alias" {
  _add_ee_slot
  _mkrepo "$HOME/proj" "git@github.com:owner/repo.git"

  cd "$HOME/proj"
  run "$REPO/bin/dot-git" use ee
  [ "$status" -eq 0 ]

  run git -C "$HOME/proj" remote get-url origin
  [ "$output" = "git@github.com-ee:owner/repo.git" ]
  run git -C "$HOME/proj" config user.email
  [ "$output" = "me@work.test" ]
}

@test "use rewrites an already-aliased origin (leaves it correct)" {
  _add_ee_slot
  _mkrepo "$HOME/proj" "git@github.com-ee:owner/repo.git"

  cd "$HOME/proj"
  run "$REPO/bin/dot-git" use ee
  [ "$status" -eq 0 ]

  run git -C "$HOME/proj" remote get-url origin
  [ "$output" = "git@github.com-ee:owner/repo.git" ]
}

@test "use is idempotent — running twice leaves a single correct origin" {
  _add_ee_slot
  _mkrepo "$HOME/proj" "https://github.com/owner/repo.git"

  cd "$HOME/proj"
  "$REPO/bin/dot-git" use ee >/dev/null
  "$REPO/bin/dot-git" use ee >/dev/null

  run bash -c "git -C '$HOME/proj' remote get-url origin | wc -l"
  [ "$output" -eq 1 ]
  run git -C "$HOME/proj" remote get-url origin
  [ "$output" = "git@github.com-ee:owner/repo.git" ]
}

@test "use errors clearly when the slot does not exist" {
  _mkrepo "$HOME/proj" "https://github.com/owner/repo.git"
  cd "$HOME/proj"
  run "$REPO/bin/dot-git" use ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"add-identity"* ]]
}

@test "use errors clearly when there is no origin remote" {
  _add_ee_slot
  mkdir -p "$HOME/proj"
  git -C "$HOME/proj" init -q
  cd "$HOME/proj"
  run "$REPO/bin/dot-git" use ee
  [ "$status" -ne 0 ]
  [[ "$output" == *"origin"* ]]
}

@test "use switches the gh account for a github-host slot" {
  _add_ee_slot
  _mkrepo "$HOME/proj" "https://github.com/owner/repo.git"

  cd "$HOME/proj"
  run "$REPO/bin/dot-git" use ee
  [ "$status" -eq 0 ]

  run cat "$GH_LOG"
  [[ "$output" == *"auth switch"* ]]
  [[ "$output" == *"workuser"* ]]
}

@test "use leaves gh untouched for a non-github-host slot" {
  "$REPO/bin/dot-git" add-identity --name acme --host gitlab.com \
    --email me@acme.test --key "$HOME/seedkey" >/dev/null
  _mkrepo "$HOME/proj" "git@gitlab.com:owner/repo.git"

  cd "$HOME/proj"
  run "$REPO/bin/dot-git" use acme
  [ "$status" -eq 0 ]

  run git -C "$HOME/proj" remote get-url origin
  [ "$output" = "git@gitlab.com-acme:owner/repo.git" ]
  run git -C "$HOME/proj" config user.email
  [ "$output" = "me@acme.test" ]

  # gh was never invoked (no log file, or empty).
  [[ ! -s "$GH_LOG" ]]
}

@test "use binds git-side even when gh is absent from PATH" {
  _add_ee_slot
  _mkrepo "$HOME/proj" "https://github.com/owner/repo.git"

  local nogh
  nogh="$(_nogh_path)"
  cd "$HOME/proj"
  run env PATH="$nogh" "$REPO/bin/dot-git" use ee
  [ "$status" -eq 0 ]

  run git -C "$HOME/proj" remote get-url origin
  [ "$output" = "git@github.com-ee:owner/repo.git" ]
  run git -C "$HOME/proj" config user.email
  [ "$output" = "me@work.test" ]
  [[ ! -s "$GH_LOG" ]]
}
