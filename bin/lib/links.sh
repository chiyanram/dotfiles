#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

########################################################
# Link resolver
########################################################
# Shared by `dot link` (plan/apply/status) and `dot reconcile` (symlink drift),
# so preview, action, and drift report never disagree on a link's state.

# classify_link <source> <target> — ok | wrong | real | missing | seeded
#
# A `.seed` source is a Seed Target (copy-once; the owning tool rewrites the live
# file, so we never symlink it). Its states are deliberately only two: `seeded`
# (target present in any form — leave it, the tool owns it) and `missing` (absent
# — needs seeding). A present file is `seeded`, NOT the `real` conflict it means
# for a symlink target. See ADR-0008.
classify_link() {
  local source="$1"
  local target="$2"
  if [[ "$source" == *.seed ]]; then
    if [ -e "$target" ] || [ -L "$target" ]; then
      echo "seeded"
    else
      echo "missing"
    fi
    return 0
  fi
  if [ -L "$target" ]; then
    local actual
    actual=$(readlink "$target")
    if [ "$actual" = "$source" ]; then
      echo "ok"
    else
      echo "wrong"
    fi
  elif [ -e "$target" ]; then
    echo "real"
  else
    echo "missing"
  fi
}

# managed_targets [config|home] — emit "<source>\t<target>\t<label>" for every
# managed target: config packages (config/<pkg> → ~/.config/<pkg>) and home
# files (home/<rel> → ~/<rel>); the optional kind emits just that slice. Single
# source of truth for "what dot link manages", so the plan and the action agree.
managed_targets() {
  local kind="${1:-all}"
  case "$kind" in all | config | home) ;; *)
    log_error "managed_targets: unknown kind '$kind' (config|home)"
    return 1
    ;;
  esac
  local config_home="${CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}}"
  local config name file rel
  if [ "$kind" != "home" ]; then
    for config in "$DOTFILES/config"/*; do
      [ -d "$config" ] || continue
      # skip empty config packages (nothing to link)
      [[ -n "$(ls -A "$config" 2>/dev/null)" ]] || continue
      name=$(basename "$config")
      printf '%s\t%s\t~/.config/%s\n' "$config" "$config_home/$name" "$name"
    done
  fi
  [ "$kind" = "config" ] && return 0
  [ -d "$DOTFILES/home" ] || return 0
  local trel
  while IFS= read -r -d '' file; do
    rel="${file#"$DOTFILES"/home/}"
    # A `home/<path>.seed` source is a Seed Target: the emitted target/label drop
    # the `.seed` suffix (home/.claude/settings.json.seed → ~/.claude/settings.json),
    # while the source keeps it so classify_link/link_apply can detect seed mode.
    # This keeps managed_targets the single source of truth — no separate list.
    if [[ "$file" == *.seed ]]; then
      trel="${rel%.seed}"
      printf '%s\t%s\t~/%s\n' "$file" "$HOME/$trel" "$trel"
    else
      printf '%s\t%s\t~/%s\n' "$file" "$HOME/$rel" "$rel"
    fi
  done < <(find "$DOTFILES/home" -type f -print0)
}
