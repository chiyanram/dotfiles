#!/usr/bin/env bash
# PostToolUse(Write|Edit): auto-format the touched bash file with this repo's
# shfmt house style (-i 2 -ci). dot-test only *checks* formatting (shfmt -d);
# this closes the loop so a formatting failure never reaches dot-test/CI.
set -Eeuo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')

[[ -n "$file_path" ]] || exit 0
case "$file_path" in
  */bin/dot* | */bin/lib/*.sh | *.sh) ;;
  *) exit 0 ;;
esac
[[ -f "$file_path" ]] || exit 0
command -v shfmt >/dev/null 2>&1 || exit 0

shfmt -i 2 -ci -w "$file_path"
