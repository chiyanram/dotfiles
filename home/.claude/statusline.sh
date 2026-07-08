#!/usr/bin/env bash
# Claude Code status line: model · dir/branch · context used+left · cost · lines
set -euo pipefail

input=$(cat)

# --- pull fields from the statusline JSON ---------------------------------
model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "?"')
model_id=$(printf '%s' "$input" | jq -r '.model.id // ""')
cur_dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // "."')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""')
cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0')
added=$(printf '%s' "$input" | jq -r '.cost.total_lines_added // 0')
removed=$(printf '%s' "$input" | jq -r '.cost.total_lines_removed // 0')

# --- colors (ANSI) --------------------------------------------------------
DIM=$'\033[2m'
RST=$'\033[0m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
BLUE=$'\033[34m'

# --- directory + git branch ----------------------------------------------
dir_name=$(basename "$cur_dir")
branch=""
if git -C "$cur_dir" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cur_dir" branch --show-current 2>/dev/null || echo "")
  if ! git -C "$cur_dir" diff --quiet 2>/dev/null || ! git -C "$cur_dir" diff --cached --quiet 2>/dev/null; then
    branch="${branch}*"
  fi
fi

# --- context window: used + remaining -------------------------------------
# Context window limit: 1M for [1m] models, else 200k.
if [[ "$model_id" == *"[1m]"* ]]; then limit=1000000; else limit=200000; fi
used=0
if [[ -n "$transcript" && -f "$transcript" ]]; then
  # Last assistant message's input+cache tokens = current context size.
  # Each transcript line is a full JSON object; take the last one with usage.
  used=$(grep '"usage"' "$transcript" 2>/dev/null | tail -1 |
    jq -r '.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)' 2>/dev/null || echo 0)
fi
[[ "$used" =~ ^[0-9]+$ ]] || used=0
pct=$((used * 100 / limit))
left=$((limit - used))

fmtk() { # humanize a token count: 47000 -> 47k, 1200000 -> 1.2M
  local n=$1
  if ((n >= 1000000)); then
    printf '%d.%dM' $((n / 1000000)) $(((n % 1000000) / 100000))
  elif ((n >= 1000)); then
    printf '%dk' $((n / 1000))
  else printf '%d' "$n"; fi
}

# color the context gauge by pressure
if ((pct >= 90)); then
  ctx_col=$RED
elif ((pct >= 70)); then
  ctx_col=$YELLOW
else ctx_col=$GREEN; fi

# --- assemble -------------------------------------------------------------
sep="${DIM} · ${RST}"
out="${MAGENTA}◆ ${model}${RST}"
out+="${sep}${BLUE}${dir_name}${RST}"
[[ -n "$branch" ]] && out+="${DIM} ⎇ ${RST}${CYAN}${branch}${RST}"
out+="${sep}${ctx_col}🧠 $(fmtk "$used")/$(fmtk "$limit") (${pct}%)${RST}${DIM} · $(fmtk "$left") left${RST}"
out+="${sep}${GREEN}\$$(printf '%.2f' "$cost")${RST}"
if ((added > 0 || removed > 0)); then
  out+="${sep}${GREEN}+${added}${RST}${DIM}/${RST}${RED}-${removed}${RST}"
fi

printf '%b' "$out"
