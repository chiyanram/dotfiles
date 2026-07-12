setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export TERM=dumb
  source "$REPO/bin/lib/git-repo-discovery.sh"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "git_slot_audit_roots prints the conventional roots under HOME" {
  run git_slot_audit_roots
  [[ "$output" == *"$HOME/work"* ]]
  [[ "$output" == *"$HOME/workspace"* ]]
  [[ "$output" == *"$HOME/dev"* ]]
  [[ "$output" == *"$HOME/dotfiles"* ]]
  [[ "$output" == *"$HOME/personal"* ]]
  [[ "$output" == *"$HOME/clients"* ]]
}

@test "git_slot_audit_roots augments the conventional set with a git_audit_roots override" {
  dot_set_config git_audit_roots "$HOME/elsewhere"
  run git_slot_audit_roots
  [[ "$output" == *"$HOME/work"* ]]
  [[ "$output" == *"$HOME/elsewhere"* ]]
}

@test "git_slot_audit_dirs finds a repo under a conventional root" {
  mkdir -p "$HOME/work/api"
  git -C "$HOME/work/api" init -q
  run git_slot_audit_dirs
  [[ "$output" == *"$HOME/work/api/.git"* ]]
}

@test "git_slot_audit_dirs finds a repo under a git_audit_roots override" {
  dot_set_config git_audit_roots "$HOME/elsewhere"
  mkdir -p "$HOME/elsewhere/api"
  git -C "$HOME/elsewhere/api" init -q
  run git_slot_audit_dirs
  [[ "$output" == *"$HOME/elsewhere/api/.git"* ]]
}

@test "git_slot_audit_dirs silently skips a conventional root that doesn't exist" {
  run git_slot_audit_dirs
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "git_slot_audit_dirs does not descend into a found repo (no nested .git hits)" {
  mkdir -p "$HOME/work/api"
  git -C "$HOME/work/api" init -q
  mkdir -p "$HOME/work/api/vendor/nested"
  git -C "$HOME/work/api/vendor/nested" init -q
  run git_slot_audit_dirs
  [[ "$output" == *"$HOME/work/api/.git"* ]]
  [[ "$output" != *"nested"* ]]
}

@test "git_slot_audit_dirs finds a repo one org level deep" {
  mkdir -p "$HOME/clients/acme/api"
  git -C "$HOME/clients/acme/api" init -q
  run git_slot_audit_dirs
  [[ "$output" == *"$HOME/clients/acme/api/.git"* ]]
}
