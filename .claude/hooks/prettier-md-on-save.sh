#!/usr/bin/env bash
# PostToolUse(Write|Edit): auto-format touched markdown with the same
# prettier version pinned in .pre-commit-config.yaml / dot-test's
# check_prettier_md, so it never disagrees with the pre-commit/CI check.
set -Eeuo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')

[[ -n "$file_path" ]] || exit 0
[[ "$file_path" == *.md ]] || exit 0
[[ -f "$file_path" ]] || exit 0
command -v npx >/dev/null 2>&1 || exit 0

npx --yes prettier@3.9.4 --write "$file_path" || true
