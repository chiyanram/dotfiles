setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks so include paths match
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export DOTFILES="$REPO"
  export TERM=dumb
  # Clean global git config (the committed one) under XDG, personal fallback identity.
  export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
  mkdir -p "$XDG_CONFIG_HOME/git"
  cp "$REPO/config/git/config" "$GIT_CONFIG_GLOBAL"
  git config -f "$HOME/.gitconfig-local" user.email "me@home.test"
  git config -f "$HOME/.gitconfig-local" user.name "Me Personal"
  # Passphrase-less seed key so add-identity never prompts.
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -C "seed@test" -f "$HOME/seedkey" >/dev/null 2>&1
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Create the ee slot (github.com, gh user "workuser") with the seed key.
_add_ee_slot() {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --github-user workuser --key "$HOME/seedkey" >/dev/null
}

# mkrepo <dir> <origin-url> — init a repo and (optionally) set its origin.
_mkrepo() {
  mkdir -p "$1"
  git -C "$1" init -q
  if [[ -n "${2:-}" ]]; then
    git -C "$1" remote add origin "$2"
  fi
}

# Run migrate, feeding <answers> (one per line) to its prompts over stdin.
_migrate() {
  run bash -c "printf '%s' \"\$1\" | '$REPO/bin/dot-git' migrate" _ "$1"
}

@test "answering yes rebinds only the mis-set repo; bound and no-remote untouched" {
  _add_ee_slot
  _mkrepo "$HOME/work/api" "https://github.com/owner/api.git"      # mis-set -> offer
  _mkrepo "$HOME/work/bound" "git@github.com-ee:owner/bound.git"   # already bound
  _mkrepo "$HOME/work/scratch" ""                                  # no origin

  _migrate $'y\n'
  [ "$status" -eq 0 ]

  # Only the mis-set repo was rewritten to the slot alias.
  run git -C "$HOME/work/api" remote get-url origin
  [ "$output" = "git@github.com-ee:owner/api.git" ]
  # And its identity now resolves to the slot's email.
  run git -C "$HOME/work/api" config user.email
  [ "$output" = "me@work.test" ]

  # The already-bound repo is unchanged.
  run git -C "$HOME/work/bound" remote get-url origin
  [ "$output" = "git@github.com-ee:owner/bound.git" ]
}

@test "answering no leaves the mis-set repo unchanged" {
  _add_ee_slot
  _mkrepo "$HOME/work/api" "https://github.com/owner/api.git"

  _migrate $'n\n'
  [ "$status" -eq 0 ]

  run git -C "$HOME/work/api" remote get-url origin
  [ "$output" = "https://github.com/owner/api.git" ]
}

@test "a mis-set repo on a host with no slot is reported and skipped" {
  # No slot exists for github.com -> misset-add: report, never prompt, never rewrite.
  _mkrepo "$HOME/work/api" "git@github.com:owner/api.git"

  _migrate ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"add-identity"* ]]
  [[ "$output" == *"work/api"* ]]

  run git -C "$HOME/work/api" remote get-url origin
  [ "$output" = "git@github.com:owner/api.git" ]
}

@test "honors a git_audit_roots override pointing at an extra directory" {
  "$REPO/bin/dot-profile" set-config git_audit_roots "$HOME/elsewhere" >/dev/null
  _add_ee_slot
  _mkrepo "$HOME/elsewhere/api" "https://github.com/owner/api.git"

  _migrate $'y\n'
  [ "$status" -eq 0 ]

  run git -C "$HOME/elsewhere/api" remote get-url origin
  [ "$output" = "git@github.com-ee:owner/api.git" ]
}

@test "re-running migrate over already-bound repos offers nothing and rewrites nothing" {
  _add_ee_slot
  _mkrepo "$HOME/work/api" "https://github.com/owner/api.git"

  _migrate $'y\n' # first pass binds it
  [ "$status" -eq 0 ]
  run git -C "$HOME/work/api" remote get-url origin
  [ "$output" = "git@github.com-ee:owner/api.git" ]

  # Second pass: nothing to offer, origin stays a single correct alias.
  _migrate ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"Bind this repo"* ]]

  run bash -c "git -C '$HOME/work/api' remote get-url origin | wc -l"
  [ "$output" -eq 1 ]
  run git -C "$HOME/work/api" remote get-url origin
  [ "$output" = "git@github.com-ee:owner/api.git" ]
}
