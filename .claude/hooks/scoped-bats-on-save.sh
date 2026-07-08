#!/usr/bin/env bash
# PostToolUse(Write|Edit): run the bats file(s) whose name matches the touched
# script, for feedback faster than a full dot-test run. Best-effort glob on
# the basename stem (bin/dot-doctor -> tests/*doctor*.bats, bin/lib/reconcile.sh
# -> tests/*reconcile*.bats) — non-blocking either way.
set -Eeuo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')

[[ -n "$file_path" ]] || exit 0
command -v bats >/dev/null 2>&1 || exit 0

repo_root=$(cd "$(dirname "$file_path")" && git rev-parse --show-toplevel 2>/dev/null) || exit 0
[[ -d "$repo_root/tests" ]] || exit 0

base=$(basename "$file_path")
case "$base" in
  dot-*) stem=${base#dot-} ;;
  *.sh) stem=${base%.sh} ;;
  *) exit 0 ;;
esac

shopt -s nullglob nocaseglob
matches=("$repo_root"/tests/*"$stem"*.bats)
shopt -u nullglob nocaseglob

[[ ${#matches[@]} -gt 0 ]] || exit 0

bats "${matches[@]}" || true
