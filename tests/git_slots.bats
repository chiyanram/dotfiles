setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX"
  export TERM=dumb
  source "$REPO/bin/lib/git-slots.sh"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "git_slot_ghuser reads github.user from the slot fragment" {
  git config -f "$HOME/.gitconfig-ee" github.user "workuser"
  run git_slot_ghuser ee
  [ "$status" -eq 0 ]
  [ "$output" = "workuser" ]
}

@test "git_slot_ghuser fails when github.user is unset in an existing fragment" {
  git config -f "$HOME/.gitconfig-ee" user.email "me@work.test"
  run git_slot_ghuser ee
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "git_slot_ghuser fails when the slot fragment doesn't exist" {
  run git_slot_ghuser nonexistent
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

_seed_identities() {
  cat >"$HOME/.gitconfig-identities" <<'EOF'
[includeIf "hasconfig:remote.*.url:git@github.com-ee:*/**"]
	path = ~/.gitconfig-ee
[includeIf "hasconfig:remote.*.url:git@gitlab.com-personal:*/**"]
	path = ~/.gitconfig-personal
EOF
}

@test "git_slot_name_for_alias resolves a known alias to its slot name" {
  _seed_identities
  run git_slot_name_for_alias github.com-ee
  [ "$status" -eq 0 ]
  [ "$output" = "ee" ]
}

@test "git_slot_name_for_alias fails on an unknown alias" {
  _seed_identities
  run git_slot_name_for_alias github.com-nope
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "git_slot_alias_for_name resolves a known slot name to its alias" {
  _seed_identities
  run git_slot_alias_for_name personal
  [ "$status" -eq 0 ]
  [ "$output" = "gitlab.com-personal" ]
}

@test "git_slot_alias_for_name fails on an unknown slot name" {
  _seed_identities
  run git_slot_alias_for_name nope
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "both direction lookups fail cleanly when ~/.gitconfig-identities doesn't exist" {
  run git_slot_name_for_alias github.com-ee
  [ "$status" -ne 0 ]
  run git_slot_alias_for_name ee
  [ "$status" -ne 0 ]
}
