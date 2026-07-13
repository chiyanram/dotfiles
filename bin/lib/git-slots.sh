#!/usr/bin/env bash
# Shared identity-slot detection — the single source of truth for the "is this
# repo's origin bound to the right slot?" question. Sourced by BOTH the Identity
# Guard (config/git/hooks/pre-commit) and `dot doctor`'s audit so the guard and
# the proactive sweep can never disagree about what counts as mis-set.
#
# Identity-slot schema queries, status classification, and repo/gh state
# resolution — no logging, no `set` options (they inherit the caller's). Not
# all read-only: git_repo_slot_name shells out to `git` against a real repo,
# and git_slot_gh_config_dir checks a real file on disk. Repo *discovery*
# (walking the filesystem for repos to check) lives in the sibling
# bin/lib/git-repo-discovery.sh instead. Slots are encoded in
# ~/.gitconfig-identities as includeIf lines whose glob embeds
# `git@<host>-<name>:` (see `dot git add-identity`); the alias is
# `<host>-<name>`. bash-3.2-safe (no assoc arrays / mapfile).

# Extract the host token from an origin URL (may itself be a slot alias for an
# scp-style URL). Prints the token; returns 1 on an unrecognized URL.
git_url_host_token() {
  local url="$1" rest
  case "$url" in
    https://* | http://*)
      rest="${url#*://}"
      printf '%s\n' "${rest%%/*}"
      ;;
    ssh://*)
      rest="${url#ssh://}" # [user@]host[:port]/owner/repo
      rest="${rest#*@}"    # drop user@
      rest="${rest%%/*}"   # host[:port]
      printf '%s\n' "${rest%%:*}"
      ;;
    *:*)
      rest="${url%%:*}" # [user@]host
      printf '%s\n' "${rest#*@}"
      ;;
    *)
      return 1
      ;;
  esac
}

# Print every slot alias (`<host>-<name>`), one per line.
git_slot_aliases() {
  local f="$HOME/.gitconfig-identities"
  [[ -f "$f" ]] || return 0
  sed -n 's/.*git@\([^:]*\):.*/\1/p' "$f"
}

# Exit 0 if <alias> is a defined slot alias.
git_slot_alias_exists() {
  local target="$1" a
  while IFS= read -r a; do
    [[ "$a" == "$target" ]] && return 0
  done < <(git_slot_aliases)
  return 1
}

# Print the slot names defined for <host> (alias `<host>-<name>` -> `<name>`).
git_slots_for_host() {
  local host="$1" a
  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    case "$a" in
      "$host"-*) printf '%s\n' "${a#"$host"-}" ;;
    esac
  done < <(git_slot_aliases)
}

# Print one "alias\tname" row per identity slot in ~/.gitconfig-identities,
# pairing each includeIf's alias with the slot name from its `path =
# ~/.gitconfig-<name>`. The single parse both direction-lookups below filter
# over, so a format change to the file only needs updating this one place.
_git_slot_identities_table() {
  local identities="$HOME/.gitconfig-identities"
  [[ -f "$identities" ]] || return 0
  awk '
    /^[ \t]*\[includeIf / {
      if (match($0, /git@[^:]+:/)) {
        alias = substr($0, RSTART + 4, RLENGTH - 5)
      }
      next
    }
    /path[ \t]*=/ {
      p = $0
      sub(/.*path[ \t]*=[ \t]*/, "", p)
      if (alias != "" && p ~ /^~\/\.gitconfig-/) {
        sub(/^~\/\.gitconfig-/, "", p)
        print alias "\t" p
      }
    }
  ' "$identities"
}

# Resolve a slot alias (`<host>-<name>`) back to its slot NAME. Prints the
# name; returns 1 if the alias isn't a slot.
git_slot_name_for_alias() {
  local want="$1" alias name found=1
  while IFS=$'\t' read -r alias name; do
    if [[ "$alias" == "$want" ]]; then
      printf '%s\n' "$name"
      found=0
      break
    fi
  done < <(_git_slot_identities_table)
  return "$found"
}

# Resolve a slot name to its SSH alias (`<host>-<name>`), the inverse of
# git_slot_name_for_alias — moved here from `dot git`'s slot_alias so both
# directions share one parse. Prints the alias; returns 1 if no slot has that
# name.
git_slot_alias_for_name() {
  local want="$1" alias name found=1
  while IFS=$'\t' read -r alias name; do
    if [[ "$name" == "$want" ]]; then
      printf '%s\n' "$alias"
      found=0
      break
    fi
  done < <(_git_slot_identities_table)
  return "$found"
}

# Print a slot's github.user (set by `dot git add-identity`/`use` for gh CLI
# sync), read from its ~/.gitconfig-<name> fragment. Returns 1 if the fragment
# or the key is missing — callers that treat "no ghuser set" as normal use
# `git_slot_ghuser "$name" || true`, same as the git-config call it replaces.
git_slot_ghuser() {
  local name="$1"
  git config -f "$HOME/.gitconfig-$name" github.user 2>/dev/null
}

# Resolve the slot NAME bound to a repo's origin, if any. Optional dir arg
# (default: cwd) — every no-arg call site means "use cwd", not a missing
# argument (shellcheck's SC2119 must be disabled at each such call site
# instead, since the directive doesn't cross files; see bin/dot-git #152).
# Returns 1 if there's no origin, the origin is unparseable, or the origin's
# host isn't bound to any slot.
git_repo_slot_name() {
  local dir="${1:-.}" url alias
  git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null || return 1
  url="$(git -C "$dir" config --get remote.origin.url 2>/dev/null)" || return 1
  [[ -n "$url" ]] || return 1
  alias="$(git_url_host_token "$url")" || return 1
  git_slot_name_for_alias "$alias"
}

# A slot's dedicated gh config dir, by convention `~/.config/gh-<name>`
# (mirrors `~/.gitconfig-<name>`) — the per-slot GH_CONFIG_DIR isolation
# ADR-0001 named and deferred ("true per-terminal isolation would need
# per-slot GH_CONFIG_DIR env"). Prints the dir only if it's an actual
# logged-in gh config (has hosts.yml); returns 1 otherwise so callers fall
# back to the default, untouched gh config instead of pointing at nothing.
git_slot_gh_config_dir() {
  local name="$1"
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/gh-$name"
  [[ -f "$dir/hosts.yml" ]] || return 1
  printf '%s\n' "$dir"
}

# Classify an origin URL against the known slots — the mis-set definition the
# Identity Guard enforces and `dot doctor` audits, in one place. Always exits 0;
# prints exactly one status token:
#   none                    empty URL (no origin) — fine
#   unparseable             URL we can't read — don't get in the way
#   unknown                 host is neither a default forge nor has any slot — fine
#   bound:<alias>           origin already uses an existing slot alias — fine
#   misset-use:<slot>:<host>  known host WITH a slot, repo not bound — mis-set
#   misset-add:<host>       default forge, no slot for it, repo not bound — mis-set
git_slot_status() {
  local url="$1" host first_slot is_forge=1
  [[ -n "$url" ]] || {
    printf 'none\n'
    return 0
  }
  if ! host="$(git_url_host_token "$url")" || [[ -z "$host" ]]; then
    printf 'unparseable\n'
    return 0
  fi
  # Origin already uses an existing slot alias -> bound.
  if git_slot_alias_exists "$host"; then
    printf 'bound:%s\n' "$host"
    return 0
  fi
  first_slot="$(git_slots_for_host "$host" | head -n 1)"
  case "$host" in
    github.com | gitlab.com | bitbucket.org) is_forge=0 ;;
  esac
  # Known host = a default forge OR a host that already has >=1 slot.
  if [[ "$is_forge" -eq 0 || -n "$first_slot" ]]; then
    if [[ -n "$first_slot" ]]; then
      printf 'misset-use:%s:%s\n' "$first_slot" "$host"
    else
      printf 'misset-add:%s\n' "$host"
    fi
    return 0
  fi
  # Unknown host (not a forge, no slot) -> fine.
  printf 'unknown\n'
}
