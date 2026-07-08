#!/usr/bin/env bash
# PostToolUse(Write|Edit): chmod +x any bin/** file that has a shebang but
# isn't executable yet — the exact bug that broke PR #64 (new bin/lib/*.sh
# files had a shebang but weren't executable, failing pre-commit's
# check-shebang-scripts-are-executable, which ./bin/dot-test does not check).
set -Eeuo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')

[[ -n "$file_path" ]] || exit 0
[[ "$file_path" == */bin/* ]] || exit 0
[[ -f "$file_path" ]] || exit 0
[[ -x "$file_path" ]] && exit 0

first_two_bytes=$(head -c2 "$file_path" 2>/dev/null || true)
[[ "$first_two_bytes" == '#!' ]] || exit 0

chmod +x "$file_path"
echo "chmod +x: $file_path (had a shebang but wasn't executable)"
