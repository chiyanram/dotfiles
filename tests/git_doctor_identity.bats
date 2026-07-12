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

  # Stub `gh` on PATH: `gh api user --jq .login` prints the login recorded for
  # $GH_CONFIG_DIR (a dedicated per-slot config, see _seed_dedicated_gh_config)
  # when one is set, otherwise whatever GH_ACTIVE holds (the single global
  # active account) -- so the audit's gh-drift check is observable for both
  # paths and the real gh is never touched.
  export GH_ACTIVE="workuser"
  mkdir -p "$HOME/bin"
  cat >"$HOME/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Only implement the one call the audit makes.
if [[ "$1" == "api" && "$2" == "user" ]]; then
  if [[ -n "${GH_CONFIG_DIR:-}" && -f "$GH_CONFIG_DIR/login" ]]; then
    cat "$GH_CONFIG_DIR/login"
  else
    printf '%s\n' "${GH_ACTIVE:-}"
  fi
  exit 0
fi
exit 0
EOF
  chmod +x "$HOME/bin/gh"
  export PATH="$HOME/bin:$PATH"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Create the ee slot (github.com, gh user "workuser") with the seed key.
_add_ee_slot() {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --github-user workuser --key "$HOME/seedkey" >/dev/null
}

# A slot's dedicated gh config: ~/.config/gh-<name>/hosts.yml (so
# git_slot_gh_config_dir resolves it) with a login file the stubbed gh reads
# back for `gh api user` when GH_CONFIG_DIR points there.
_seed_dedicated_gh_config() {
  local name="$1" login="$2"
  mkdir -p "$HOME/.config/gh-$name"
  printf 'github.com:\n    user: %s\n' "$login" >"$HOME/.config/gh-$name/hosts.yml"
  printf '%s\n' "$login" >"$HOME/.config/gh-$name/login"
}

# mkrepo <dir> <origin-url> — init a repo and (optionally) set its origin.
_mkrepo() {
  mkdir -p "$1"
  git -C "$1" init -q
  if [[ -n "${2:-}" ]]; then
    git -C "$1" remote add origin "$2"
  fi
}

# Run just the audit (main is guarded when the script is sourced).
_run_audit() {
  run bash -c "source '$REPO/bin/dot-doctor'; check_identity_audit"
}

@test "lists a repo whose origin is a known forge with no matching slot" {
  _mkrepo "$HOME/work/api" "git@github.com:owner/api.git"
  _run_audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"work/api"* ]]
  [[ "$output" == *"add-identity"* ]]
}

@test "points at 'dot git use <slot>' when a slot exists for the host" {
  _add_ee_slot
  _mkrepo "$HOME/work/api" "git@github.com:owner/api.git" # plain URL, not the alias
  _run_audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"work/api"* ]]
  [[ "$output" == *"dot git use ee"* ]]
}

@test "does not list a repo already bound to a slot alias" {
  _add_ee_slot
  _mkrepo "$HOME/work/api" "git@github.com-ee:owner/api.git"
  _run_audit
  [ "$status" -eq 0 ]
  [[ "$output" != *"work/api"* ]]
  [[ "$output" == *"no identity or gh-account drift"* ]]
}

@test "does not list a repo with no origin remote" {
  _mkrepo "$HOME/dev/scratch" "" # no origin
  _run_audit
  [ "$status" -eq 0 ]
  [[ "$output" != *"dev/scratch"* ]]
  [[ "$output" == *"no identity or gh-account drift"* ]]
}

@test "honors a git_audit_roots override pointing at an extra directory" {
  "$REPO/bin/dot-profile" set-config git_audit_roots "$HOME/elsewhere" >/dev/null
  _mkrepo "$HOME/elsewhere/api" "git@github.com:owner/api.git"
  _run_audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"elsewhere/api"* ]]
  [[ "$output" == *"add-identity"* ]]
}

@test "an absent conventional root causes no error and no noise" {
  # No roots exist at all in a bare sandbox HOME.
  _run_audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"no identity or gh-account drift"* ]]
  [[ "$output" != *"No such file"* ]]
  [[ "$output" != *"error"* ]]
}

@test "warns on gh drift when the active account differs from the slot's" {
  _add_ee_slot # slot ee expects gh account "workuser"
  export GH_ACTIVE="someoneelse"
  _mkrepo "$HOME/work/api" "git@github.com-ee:owner/api.git" # bound to ee
  _run_audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh drift"* ]]
  [[ "$output" == *"work/api"* ]]
  [[ "$output" == *"workuser"* ]]
  [[ "$output" == *"someoneelse"* ]]
}

@test "no gh-drift warning when the active account matches the slot's" {
  _add_ee_slot
  export GH_ACTIVE="workuser" # matches the slot
  _mkrepo "$HOME/work/api" "git@github.com-ee:owner/api.git"
  _run_audit
  [ "$status" -eq 0 ]
  [[ "$output" != *"gh drift"* ]]
}

@test "gh drift is judged against a slot's dedicated config, ignoring the global active account" {
  _add_ee_slot # slot ee expects gh account "workuser"
  export GH_ACTIVE="someoneelse" # global active is wrong, but irrelevant once dedicated exists
  _seed_dedicated_gh_config ee workuser
  _mkrepo "$HOME/work/api" "git@github.com-ee:owner/api.git"
  _run_audit
  [ "$status" -eq 0 ]
  [[ "$output" != *"gh drift"* ]]
}

@test "gh drift still fires when a slot's dedicated config itself is wrong" {
  _add_ee_slot # slot ee expects gh account "workuser"
  export GH_ACTIVE="workuser" # global active is right, but the dedicated config is what counts now
  _seed_dedicated_gh_config ee someoneelse
  _mkrepo "$HOME/work/api" "git@github.com-ee:owner/api.git"
  _run_audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh drift"* ]]
  [[ "$output" == *"dedicated config"* ]]
  [[ "$output" == *"workuser"* ]]
  [[ "$output" == *"someoneelse"* ]]
}

@test "the audit performs no writes to repos or config" {
  _add_ee_slot
  _mkrepo "$HOME/work/api" "git@github.com:owner/api.git"
  export GH_ACTIVE="someoneelse"
  # Content-hash every file in the sandbox before and after; the origin URL too.
  local before after before_origin after_origin
  before="$(cd "$SANDBOX" && find . -type f -exec cksum {} \; 2>/dev/null | sort)"
  before_origin="$(git -C "$HOME/work/api" remote get-url origin)"
  _run_audit
  [ "$status" -eq 0 ]
  after="$(cd "$SANDBOX" && find . -type f -exec cksum {} \; 2>/dev/null | sort)"
  after_origin="$(git -C "$HOME/work/api" remote get-url origin)"
  [ "$before" = "$after" ]
  [ "$before_origin" = "$after_origin" ]
}
