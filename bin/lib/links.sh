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

# link_state_is_issue <state> — true (0) if the Link State is a problem
# (wrong/real/missing), false (1) if healthy (ok/seeded). The shared
# health-axis predicate for every status-reporting call site (link_status,
# dot-doctor's check_config_links/check_home_links) so they can't drift on
# what counts as "fine" (#145). NOT used by link_plan (colors by action, not
# health) or link_apply/unlink_apply (mutation dispatch, not status).
link_state_is_issue() {
  case "$1" in
    ok | seeded) return 1 ;;
    wrong | real | missing) return 0 ;;
    *)
      log_error "link_state_is_issue: unknown state '$1'"
      return 2
      ;;
  esac
}

# link_state_color <state> — the $GREEN/$YELLOW/$RED value for a Link State on
# the same health axis as link_state_is_issue (missing reads red, same as
# wrong/real; seeded reads green, same as ok). Shared so status-reporting call
# sites can't drift on what color reports a state (#145).
link_state_color() {
  case "$1" in
    ok | seeded) echo "$GREEN" ;;
    wrong) echo "$YELLOW" ;;
    real | missing) echo "$RED" ;;
    *)
      log_error "link_state_color: unknown state '$1'"
      return 1
      ;;
  esac
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
    # Prune `*.seed` DIRECTORIES: a Seed Target is a single file copied verbatim
    # (link_apply does `cp`, not `cp -R`). Without this, files inside a `foo.seed/`
    # dir would be emitted as normal symlink targets under ~/foo.seed/ — a mess.
    # A pruned `.seed` dir is simply unmanaged (safe) rather than mis-linked (#119).
  done < <(find "$DOTFILES/home" \( -type d -name '*.seed' -prune \) -o -type f -print0)
}
