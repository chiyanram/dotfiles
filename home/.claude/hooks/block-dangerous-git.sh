#!/usr/bin/env bash
# Description: Claude Code PreToolUse hook — refuse destructive git commands.
#
# See docs/agents/claude-automations.md for what this guards and why. Rules that
# only make sense while reading the code live here:
#
# NOT `set -e` (the repo default is `set -Eeuo pipefail`). Claude Code treats
# exit 2 as "refuse" and any other non-zero as a non-blocking error, so a hook
# that dies mid-check fails OPEN. Dropping `-e` keeps the guard reaching its own
# decision instead of aborting into a permissive one.
#
# No `common.sh`, no DOTFILES resolution. Unlike a `dot-*` script this runs from
# ~/.claude on any machine, including before the repo is cloned, so it must stand
# alone.
set -uo pipefail

INPUT=$(cat)

# Degrade closed, not open: without jq the command can't be lifted out of the
# payload, and exiting 0 would disable the guard on exactly the machine whose
# setup is broken. Fall back to scanning the raw JSON instead — coarser, and it
# costs the prose-safety below, but it is never silent.
parsed=true
if COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) &&
  [ -n "$COMMAND" ]; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
else
  parsed=false
  COMMAND="$INPUT"
  CWD=""
fi
[ -n "$CWD" ] || CWD="$PWD"
[ -n "$COMMAND" ] || exit 0

# Which repo owns this hook? `dot link` symlinks with an absolute source, so one
# readlink resolves it; home/.claude/hooks/<this> means the root is three up.
# Running the file directly (tests, a hand-copied install) works too — the path
# is then already the real one.
self="${BASH_SOURCE[0]}"
[ -L "$self" ] && self="$(readlink "$self")"
hook_dir="$(cd "$(dirname "$self")" 2>/dev/null && pwd -P)" || hook_dir=""
owning_repo=""
[ -n "$hook_dir" ] && owning_repo="$(cd "$hook_dir/../../.." 2>/dev/null && pwd -P)"

trusted_repos() {
  [ -n "$owning_repo" ] && printf '%s\n' "$owning_repo"
  local sink="$HOME/.claude/hooks/trusted-git-repos.local"
  [ -f "$sink" ] || return 0
  # Skip blanks and comments — an empty entry would be a prefix matching every
  # path, silently trusting everything.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '' | '#'*) continue ;;
    esac
    printf '%s\n' "$line"
  done <"$sink"
}

is_trusted=false
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  case "$CWD" in
    "$repo" | "$repo"/*)
      is_trusted=true
      break
      ;;
  esac
done <<EOF
$(trusted_repos)
EOF

# Anchor matches to command position — line start, or after a ; & | separator —
# so the guard fires on an invocation and not on prose quoting one. `(` is
# deliberately NOT a separator here: parenthesised prose ("forced pushes (git
# push --force)") is far commoner than a bare subshell invocation, and a chained
# one is still caught by the && inside it. Known limit: grep is line-oriented,
# so a heredoc line that begins with a guarded command is indistinguishable from
# a real newline-separated one and will still be refused.
if [ "$parsed" = true ]; then
  cmd_pos='(^|[;&|])[[:space:]]*'
else
  # Raw JSON: the command sits inside `"command":"…"`, so a separator anchor
  # could never match. Accept any non-word character before `git`.
  cmd_pos='(^|[^[:alnum:]_-])[[:space:]]*'
fi
args='[^;&|]*' # one command's worth of arguments — stop at a separator

dangerous=(
  "${cmd_pos}git[[:space:]]+reset${args}--hard"
  "${cmd_pos}git[[:space:]]+clean${args}-[a-zA-Z]*f"
  "${cmd_pos}git[[:space:]]+branch${args}-D"
  "${cmd_pos}git[[:space:]]+checkout[[:space:]]+\."
  "${cmd_pos}git[[:space:]]+restore[[:space:]]+\."
  "${cmd_pos}git[[:space:]]+push${args}--force"
  "${cmd_pos}git[[:space:]]+push${args}force-with-lease"
)

guarded=(
  "${cmd_pos}git[[:space:]]+commit"
  "${cmd_pos}git[[:space:]]+push"
)

matches_any() {
  local pattern
  for pattern in "$@"; do
    printf '%s' "$COMMAND" | grep -qE "$pattern" && return 0
  done
  return 1
}

refuse() {
  printf 'BLOCKED: %s\n' "$1" >&2
  exit 2
}

if matches_any "${dangerous[@]}"; then
  refuse "'$COMMAND' is a destructive git command. The user has prevented you from doing this."
fi

if [ "$is_trusted" = false ] && matches_any "${guarded[@]}"; then
  refuse "'$COMMAND' writes git history outside a trusted repo ($CWD). The user has prevented you from doing this. Add the repo to ~/.claude/hooks/trusted-git-repos.local to allow it."
fi

exit 0
