#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

########################################################
# Homebrew profile bundles
########################################################

# Print the Brewfile paths for the active (or given) profile: core, then the
# profile-specific file if it exists.
dot_brewfiles() {
  local profile="${1:-$(dot_profile)}" dir
  dir="${DOTFILES:?DOTFILES must be set}/brew"
  [[ -f "$dir/Brewfile.core" ]] && printf '%s\n' "$dir/Brewfile.core"
  [[ -f "$dir/Brewfile.$profile" ]] && printf '%s\n' "$dir/Brewfile.$profile"
  return 0
}

# Resolve the Docker runtime: the docker_runtime config override, else the
# profile default (work -> rancher, otherwise docker-desktop).
dot_docker_runtime() {
  local runtime
  runtime="$(dot_config docker_runtime)"
  if [[ -z "$runtime" ]]; then
    case "$(dot_profile)" in
      work) runtime="rancher" ;;
      *) runtime="docker-desktop" ;;
    esac
  fi
  printf '%s\n' "$runtime"
}

# Print the brew-bundle entry/entries for a Docker runtime; return 1 if unknown.
dot_docker_runtime_entries() {
  case "${1:-}" in
    docker-desktop) printf "%s\n" "cask 'docker-desktop'" ;;
    rancher) printf "%s\n" "cask 'rancher'" ;;
    colima) printf "%s\n%s\n" "brew 'colima'" "brew 'docker'" ;;
    *) return 1 ;;
  esac
}
