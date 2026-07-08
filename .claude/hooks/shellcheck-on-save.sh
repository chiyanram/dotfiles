#!/usr/bin/env bash
# PostToolUse(Write|Edit): run shellcheck on the touched bash file for fast
# feedback. Non-blocking — mirrors dot-test's check_shellcheck tolerance for a
# missing linter, and never fails the tool call regardless of findings.
set -Eeuo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')

[[ -n "$file_path" ]] || exit 0
case "$file_path" in
  */bin/dot* | */bin/lib/*.sh | *.sh) ;;
  *) exit 0 ;;
esac
[[ -f "$file_path" ]] || exit 0
command -v shellcheck >/dev/null 2>&1 || exit 0

shellcheck -x "$file_path" || true
