setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export DOTFILES="$SANDBOX/dotfiles"
  export TERM=dumb
  mkdir -p "$DOTFILES/brew"
  printf "brew 'git'\n" >"$DOTFILES/brew/Brewfile.core"
  printf "# personal\n" >"$DOTFILES/brew/Brewfile.personal"
  printf "# work\n" >"$DOTFILES/brew/Brewfile.work"
  source "$REPO/bin/lib/common.sh"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "dot_brewfiles defaults to core + personal when profile unset" {
  run dot_brewfiles
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"/brew/Brewfile.core" ]]
  [[ "${lines[1]}" == *"/brew/Brewfile.personal" ]]
}

@test "dot_brewfiles work returns core + work" {
  run dot_brewfiles work
  [[ "${lines[0]}" == *"/brew/Brewfile.core" ]]
  [[ "${lines[1]}" == *"/brew/Brewfile.work" ]]
}

@test "dot_brewfiles omits a missing profile file" {
  rm -f "$DOTFILES/brew/Brewfile.work"
  run dot_brewfiles work
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"/brew/Brewfile.core" ]]
}

@test "dot_docker_runtime defaults to docker-desktop for personal" {
  run dot_docker_runtime
  [ "$output" = "docker-desktop" ]
}

@test "dot_docker_runtime defaults to rancher for work" {
  dot_set_profile work
  run dot_docker_runtime
  [ "$output" = "rancher" ]
}

@test "dot_docker_runtime honors the config override" {
  dot_set_profile work
  dot_set_config docker_runtime colima
  run dot_docker_runtime
  [ "$output" = "colima" ]
}

@test "dot_docker_runtime_entries maps docker-desktop" {
  run dot_docker_runtime_entries docker-desktop
  [ "$output" = "cask 'docker-desktop'" ]
}

@test "dot_docker_runtime_entries maps rancher" {
  run dot_docker_runtime_entries rancher
  [ "$output" = "cask 'rancher'" ]
}

@test "dot_docker_runtime_entries colima includes the docker cli" {
  run dot_docker_runtime_entries colima
  [[ "$output" == *"brew 'colima'"* ]]
  [[ "$output" == *"brew 'docker'"* ]]
}

@test "dot_docker_runtime_entries rejects an unknown runtime" {
  run dot_docker_runtime_entries frobnicate
  [ "$status" -ne 0 ]
}
