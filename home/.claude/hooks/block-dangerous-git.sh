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

# Git accepts global options BETWEEN the executable and the subcommand, so
# `git -C /path push --force` never matched a `git[[:space:]]+push` anchor and
# sailed through every rule below. The same hole applied to `-c`, `--git-dir`,
# `--no-pager` and friends, and to reset/clean/branch as much as to push.
#
# The option forms are enumerated rather than accepting any `-…` token followed
# by an optional value. That shortcut looks equivalent and is not: it lets
# `git --no-pager push` consume `push` as --no-pager's value, so the pattern
# stops matching and the guard fails open again — the same bug one layer down.
gitopt_val='(-[cC]|--(git-dir|work-tree|namespace|exec-path|config-env))[[:space:]]*=?[[:space:]]*[^[:space:];&|]+'
gitopt_flag='--(no-pager|paginate|bare|literal-pathspecs|no-replace-objects|no-optional-locks)|-[pP]'
gitopts="([[:space:]]+(${gitopt_val}|${gitopt_flag}))*[[:space:]]+"

dangerous=(
  "${cmd_pos}git${gitopts}reset${args}--hard"
  "${cmd_pos}git${gitopts}clean${args}-[a-zA-Z]*f"
  "${cmd_pos}git${gitopts}branch${args}-D"
  "${cmd_pos}git${gitopts}checkout[[:space:]]+\."
  "${cmd_pos}git${gitopts}restore[[:space:]]+\."
  "${cmd_pos}git${gitopts}push${args}--force"
  "${cmd_pos}git${gitopts}push${args}force-with-lease"
)

guarded=(
  "${cmd_pos}git${gitopts}commit"
  "${cmd_pos}git${gitopts}push"
)

matches_any() {
  local pattern
  for pattern in "$@"; do
    printf '%s' "$COMMAND" | grep -qE "$pattern" && return 0
  done
  return 1
}

# Escalate to the human rather than refusing outright: `permissionDecision:
# "ask"` makes Claude Code show its normal permission prompt, so the command is
# one keypress away instead of unavailable. Exit 0 — a PreToolUse hook exiting 2
# blocks the call outright and never reaches the user, which is the behaviour
# this replaces.
#
# The point was always a checkpoint, not a wall. A guard that cannot be
# overridden gets worked around: the agent reaches for a shape the pattern does
# not match (`git -C …` was exactly that), and then nobody is prompted at all.
# Asking keeps the human in the loop on the commands that matter without
# inviting anyone to route around it.
ask() {
  local reason="$1" payload
  # Test that jq PRODUCED something, not that it exists. `command -v jq` passes
  # for a jq that is present and broken — which is what the no-jq test installs —
  # and the hook would then exit 0 having printed nothing, i.e. allow the command
  # with no prompt at all. Failing open is the one outcome worse than blocking.
  if payload=$(jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}' 2>/dev/null) &&
    [ -n "$payload" ]; then
    printf '%s\n' "$payload"
    exit 0
  fi
  # No usable jq, so a well-formed decision cannot be emitted and a malformed one
  # would be ignored. Degrade closed, consistent with the raw-JSON fallback above.
  printf 'BLOCKED (jq unavailable, cannot request confirmation): %s\n' "$reason" >&2
  exit 2
}

if matches_any "${dangerous[@]}"; then
  ask "'$COMMAND' is a destructive git command. Confirm you want it to run."
fi

if [ "$is_trusted" = false ] && matches_any "${guarded[@]}"; then
  ask "'$COMMAND' writes git history outside a trusted repo ($CWD). Confirm, or add the repo to ~/.claude/hooks/trusted-git-repos.local to stop being asked."
fi

exit 0
