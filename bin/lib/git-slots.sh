#!/usr/bin/env bash
# Shared identity-slot detection — the single source of truth for the "is this
# repo's origin bound to the right slot?" question. Sourced by BOTH the Identity
# Guard (config/git/hooks/pre-commit) and `dot doctor`'s audit so the guard and
# the proactive sweep can never disagree about what counts as mis-set.
#
# Pure helpers only: no logging, no side effects, no `set` options (they inherit
# the caller's). Slots are encoded in ~/.gitconfig-identities as includeIf lines
# whose glob embeds `git@<host>-<name>:` (see `dot git add-identity`); the alias
# is `<host>-<name>`. bash-3.2-safe (no assoc arrays / mapfile).

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

# Resolve a slot alias (`<host>-<name>`) back to its slot NAME via the include's
# `path = ~/.gitconfig-<name>` in ~/.gitconfig-identities (the inverse of
# `dot git`'s slot_alias). Prints the name; returns 1 if the alias isn't a slot.
git_slot_name_for_alias() {
  local want="$1" identities="$HOME/.gitconfig-identities"
  [[ -f "$identities" ]] || return 1
  awk -v want="$want" '
    /^[ \t]*\[includeIf / {
      if (match($0, /git@[^:]+:/)) {
        alias = substr($0, RSTART + 4, RLENGTH - 5)
      }
      next
    }
    /path[ \t]*=/ {
      p = $0
      sub(/.*path[ \t]*=[ \t]*/, "", p)
      if (alias == want && p ~ /^~\/\.gitconfig-/) {
        sub(/^~\/\.gitconfig-/, "", p)
        print p
        found = 1
        exit
      }
    }
    END { if (!found) exit 1 }
  ' "$identities"
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
