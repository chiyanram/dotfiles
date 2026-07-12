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

@test "git_url_host_token extracts the host from an https URL" {
  run git_url_host_token "https://github.com/owner/repo.git"
  [ "$output" = "github.com" ]
}

@test "git_url_host_token extracts the host from a plain scp-style URL" {
  run git_url_host_token "git@github.com:owner/repo.git"
  [ "$output" = "github.com" ]
}

@test "git_url_host_token extracts the host from a scp-style URL with a subgroup path" {
  run git_url_host_token "git@gitlab.com:group/subgroup/repo.git"
  [ "$output" = "gitlab.com" ]
}

@test "git_url_host_token extracts the host from an ssh:// URL with a user" {
  run git_url_host_token "ssh://git@gitlab.com/group/subgroup/repo.git"
  [ "$output" = "gitlab.com" ]
}

@test "git_url_host_token extracts the host from an ssh:// URL with a user and port" {
  run git_url_host_token "ssh://git@gitlab.com:2222/group/subgroup/repo.git"
  [ "$output" = "gitlab.com" ]
}

@test "git_url_host_token extracts the host from an ssh:// URL without a user" {
  run git_url_host_token "ssh://gitlab.com:2222/group/repo.git"
  [ "$output" = "gitlab.com" ]
}

@test "git_url_host_token fails on an unparseable URL" {
  run git_url_host_token "not-a-url"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "git_slot_status is 'none' for an empty URL" {
  run git_slot_status ""
  [ "$output" = "none" ]
}

@test "git_slot_status is 'unparseable' for a URL with no recognizable host" {
  run git_slot_status "not-a-url"
  [ "$output" = "unparseable" ]
}

@test "git_slot_status is 'unknown' for a non-forge host with no slot" {
  run git_slot_status "https://git.internal.example/owner/repo.git"
  [ "$output" = "unknown" ]
}

@test "git_slot_status is 'bound:<alias>' when origin already uses a slot alias" {
  _seed_identities
  run git_slot_status "git@github.com-ee:owner/repo.git"
  [ "$output" = "bound:github.com-ee" ]
}

@test "git_slot_status is 'misset-use:<slot>:<host>' when a slot exists for the host but origin isn't bound" {
  _seed_identities
  run git_slot_status "git@github.com:owner/repo.git"
  [ "$output" = "misset-use:ee:github.com" ]
}

@test "git_slot_status is 'misset-add:<host>' for a default forge with no slot at all" {
  run git_slot_status "https://github.com/owner/repo.git"
  [ "$output" = "misset-add:github.com" ]
}
