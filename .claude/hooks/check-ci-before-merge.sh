#!/usr/bin/env bash
# PreToolUse(Bash): block `gh pr merge` unless every required CI check on that
# PR has actually passed. main had no branch protection at all — 5 PRs in a
# row merged with a red "Lint & tests" job and nobody noticed (the macOS job
# still passed). Until branch protection is set up server-side, this is the
# local gate: no merge lands through Claude Code without a green `gh pr checks`.
set -Eeuo pipefail

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

case "$command" in
  *gh\ pr\ merge*) ;;
  *) exit 0 ;;
esac

# Pull the PR ref (number/URL/branch) if one was given right after `merge`;
# otherwise `gh pr checks` with no args infers it from the current branch.
pr_ref=""
read -ra words <<<"$command"
for ((i = 0; i < ${#words[@]}; i++)); do
  if [[ "${words[i]}" == "merge" && "${words[i - 1]:-}" == "pr" ]]; then
    next="${words[i + 1]:-}"
    [[ -n "$next" && "$next" != -* ]] && pr_ref="$next"
    break
  fi
done

if [[ -n "$pr_ref" ]]; then
  checks_output=$(gh pr checks "$pr_ref" 2>&1) && checks_status=0 || checks_status=$?
else
  checks_output=$(gh pr checks 2>&1) && checks_status=0 || checks_status=$?
fi

if [[ "$checks_status" -ne 0 ]]; then
  reason="Blocked: CI is not all-green for this PR, so \`$command\` was refused.
$checks_output

Fix or wait for CI, then retry. To bypass intentionally, run the merge yourself outside Claude Code."
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
fi
