#!/usr/bin/env bash
# PreToolUse(Edit|Write): block identity/auth/transport git config from
# landing in the shared, symlinked config/git/config. Per CLAUDE.md, that
# config must live in ~/.gitconfig-local (personal, uncommitted) instead —
# this is the same class of bug as issue #58 (config drift from per-machine
# data leaking into a symlinked config/* dir).
set -Eeuo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')

case "$file_path" in
  */config/git/config) ;;
  *) exit 0 ;;
esac

new_content=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // empty')

if printf '%s' "$new_content" | grep -qiE 'insteadof|signingkey|^[[:space:]]*email[[:space:]]*='; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "config/git/config is shared and symlinked across machines — identity/auth/transport config (url.insteadOf, user.email, signingkey) must go in ~/.gitconfig-local instead. See CLAUDE.md, Config Management."
    }
  }'
fi
