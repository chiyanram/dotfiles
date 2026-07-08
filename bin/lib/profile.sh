#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

########################################################
# Profile / machine config
########################################################
# State lives under $XDG_CONFIG_HOME/dotfiles/ — never committed.
# profile: a single word (personal|work). config: key=value lines.

_dot_state_dir() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"; }

# Print the active profile, defaulting to personal when unset/invalid.
dot_profile() {
  local file p="personal"
  file="$(_dot_state_dir)/profile"
  if [[ -f "$file" ]]; then
    p="$(tr -d '[:space:]' <"$file")"
  fi
  [[ "$p" == "personal" || "$p" == "work" ]] || p="personal"
  printf '%s\n' "$p"
}

# Persist the active profile. Rejects anything but personal|work.
dot_set_profile() {
  local name="${1:-}" dir
  if [[ "$name" != "personal" && "$name" != "work" ]]; then
    log_error "Invalid profile: '$name' (must be 'personal' or 'work')"
    return 1
  fi
  dir="$(_dot_state_dir)"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  printf '%s\n' "$name" >"$dir/profile"
}

# Print the value for a config key. Prints one (possibly empty) line when the
# file exists; prints nothing when the file is absent. Command-substitution
# callers (`$(dot_config key)`) see "" in all absent cases. Always exits 0.
dot_config() {
  local key="${1:-}" file line value=""
  file="$(_dot_state_dir)/config"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" == "$key="* ]] && value="${line#*=}"
  done <"$file"
  printf '%s\n' "$value"
}

# Upsert key=value: replace the existing key= line in place, else append.
dot_set_config() {
  local key="${1:-}" value="${2:-}" dir file tmp line found=0
  dir="$(_dot_state_dir)"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  file="$dir/config"
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == "$key="* ]]; then
        printf '%s=%s\n' "$key" "$value"
        found=1
      else
        printf '%s\n' "$line"
      fi
    done <"$file"
  fi >"$tmp"
  [[ "$found" -eq 0 ]] && printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv "$tmp" "$file"
}
