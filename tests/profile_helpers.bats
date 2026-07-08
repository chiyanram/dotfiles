setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export TERM=dumb
  source "$REPO/bin/lib/profile.sh"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "dot_profile defaults to personal when unset" {
  run dot_profile
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "dot_set_profile then dot_profile round-trips work" {
  dot_set_profile work
  run dot_profile
  [ "$output" = "work" ]
}

@test "dot_set_profile rejects an invalid profile" {
  run dot_set_profile staging
  [ "$status" -ne 0 ]
}

@test "dot_profile falls back to personal on a garbage file" {
  mkdir -p "$XDG_CONFIG_HOME/dotfiles"
  printf 'garbage\n' >"$XDG_CONFIG_HOME/dotfiles/profile"
  run dot_profile
  [ "$output" = "personal" ]
}

@test "dot_config returns empty for an unset key" {
  run dot_config work_dir
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "dot_set_config then dot_config round-trips a value" {
  dot_set_config work_dir "$HOME/work"
  run dot_config work_dir
  [ "$output" = "$HOME/work" ]
}

@test "dot_set_config updates an existing key without duplicating it" {
  dot_set_config docker_runtime docker-desktop
  dot_set_config docker_runtime rancher
  run dot_config docker_runtime
  [ "$output" = "rancher" ]
  run grep -c '^docker_runtime=' "$XDG_CONFIG_HOME/dotfiles/config"
  [ "$output" = "1" ]
}

@test "dot_set_config preserves other keys" {
  dot_set_config work_dir "$HOME/work"
  dot_set_config docker_runtime rancher
  run dot_config work_dir
  [ "$output" = "$HOME/work" ]
}

@test "dot_config preserves a value that contains =" {
  dot_set_config repo_url "https://example.com/a=b"
  run dot_config repo_url
  [ "$output" = "https://example.com/a=b" ]
}
