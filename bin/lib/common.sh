#!/usr/bin/env bash

setup_colors() {
  # Check if function has already run
  if [[ -n "${SETUP_COLORS_COMPLETE:-}" ]]; then
    return 0
  fi

  # Check if colors should be enabled
  local use_colors=true
  if [[ ! -t 2 ]] || [[ -n "${NO_COLOR-}" ]] || [[ "${TERM-}" == "dumb" ]]; then
    use_colors=false
  fi

  # Function to set a readonly variable with conditional value
  set_color() {
    local var_name=$1
    local color_value=$2
    if [[ "$use_colors" == true ]]; then
      readonly "$var_name=$color_value"
    else
      readonly "$var_name="
    fi
  }

  # Basic formatting
  set_color RESET "\033[0m"
  set_color BOLD "\033[1m"
  set_color DIM "\033[2m"
  set_color UNDERLINE "\033[4m"

  # Standard colors
  set_color BLUE "\033[34m"
  set_color GREEN "\033[32m"
  set_color YELLOW "\033[33m"
  set_color RED "\033[31m"
  set_color CYAN "\033[36m"
  set_color MAGENTA "\033[35m"
  set_color BLACK "\033[30m"

  # Bright colors
  set_color BRIGHT_BLACK "\033[90m"
  set_color BRIGHT_BLUE "\033[94m"
  set_color BRIGHT_GREEN "\033[92m"
  set_color BRIGHT_YELLOW "\033[93m"
  set_color BRIGHT_RED "\033[91m"
  set_color BRIGHT_CYAN "\033[96m"
  set_color BRIGHT_MAGENTA "\033[95m"

  # Background colors
  set_color BG_BLACK "\033[40m"
  set_color BG_BLUE "\033[44m"
  set_color BG_BRIGHT_BLUE "\033[104m"
  set_color BG_MAGENTA "\033[45m"
  set_color BG_BRIGHT_MAGENTA "\033[105m"
  set_color BG_GREEN "\033[42m"
  set_color BG_BRIGHT_GREEN "\033[102m"
  set_color BG_CYAN "\033[46m"
  set_color BG_BRIGHT_CYAN "\033[106m"

  # Icons
  set_color INFO_ICON "ℹ"
  set_color SUCCESS_ICON "✔"
  set_color WARNING_ICON "⚠"
  set_color ERROR_ICON "✖"

  SETUP_COLORS_COMPLETE=1
}

# Enhanced logging functions with icons and colored text
log_info() { printf "${BRIGHT_BLUE}${BOLD}${INFO_ICON}${RESET} ${BLUE}%s${RESET}\n" "$1"; }
log_success() { printf "${BRIGHT_GREEN}${BOLD}${SUCCESS_ICON}${RESET} ${GREEN}%s${RESET}\n" "$1"; }
log_warning() { printf "${BRIGHT_YELLOW}${BOLD}${WARNING_ICON}${RESET} ${YELLOW}%s${RESET}\n" "$1"; }
log_error() { printf "${BRIGHT_RED}${BOLD}${ERROR_ICON}${RESET} ${RED}%s${RESET}\n" "$1" >&2; }

# Helper for formatted output
fmt_key() { printf "${CYAN}${BOLD}%s${RESET}" "$1"; }
fmt_value() { printf "${BRIGHT_CYAN}%s${RESET}" "$1"; }
fmt_cmd() { printf "${MAGENTA}${BOLD}%s${RESET}" "$1"; }
fmt_path() { printf "${BRIGHT_BLUE}%s${RESET}" "$1"; }
fmt_title() { printf "${BRIGHT_BLUE}${BOLD} %s ${RESET}\n" "$1"; }
fmt_title_underline() { printf "${BRIGHT_BLUE}${BOLD}${UNDERLINE}%s${RESET}\n" "$1"; }
fmt_title_border() {
  local text="$1"
  local len=${#text}
  printf "${BRIGHT_BLUE}${BOLD}┌─%s─┐${RESET}\n" "$(printf '─%.0s' $(seq "$len"))"
  printf "${BRIGHT_BLUE}${BOLD}│ %s │${RESET}\n" "$text"
  printf "${BRIGHT_BLUE}${BOLD}└─%s─┘${RESET}\n" "$(printf '─%.0s' $(seq "$len"))"
}

# Enhanced spinner class with multiple style options and colors
spinner() {
  local pid=$1                 # Process ID to monitor
  local style=${2:-1}          # Spinner style (default: 0)
  local delay=0.1              # Animation delay
  local msg="${3:-Working...}" # Custom message
  local logfile="${4:-}"       # Optional log to live-tail

  local RAINBOW=("$RED" "$YELLOW" "$GREEN" "$CYAN" "$BLUE" "$MAGENTA")

  # Different spinner styles
  case $style in
    1) local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' ;;     # Braille dots
    2) local chars='▁▂▃▄▅▆▇█▇▆▅▄▃▂' ;; # Growing bars
    3) local chars='←↖↑↗→↘↓↙' ;;       # Arrows
    4) local chars='▉▊▋▌▍▎▏▎▍▌▋▊▉' ;;  # Thickness varying bar
    5) local chars='▖▘▝▗' ;;           # Box corners
    6) local chars='┤┘┴└├┌┬┐' ;;       # Box borders
    7) local chars='◢◣◤◥' ;;           # Diamond parts
    8) local chars='◰◳◲◱' ;;           # Box quadrants
    9) local chars='◴◷◶◵' ;;           # Circle quadrants
    10) local chars='◐◓◑◒' ;;          # Circle halves
    11) local chars='⣾⣽⣻⢿⡿⣟⣯⣷' ;;      # Complex braille
    12) local chars='•●○' ;;           # Growing circle
    13) local chars='✶✸✹✺✹✸' ;;        # Spiky star
    14) local chars='⠁⠂⠄⡀⢀⠠⠐⠈' ;;      # Growing braille
    15) local chars='≈≋≋≈≈≋≋≈' ;;      # Waves
    16) local chars='⌜⌝⌟⌞' ;;          # Corner pieces
    17) local chars='◜◝◞◟' ;;          # Curved corners
    18) local chars='⬖⬘⬗⬙' ;;          # Triangles
    19) local chars='⏳⌛' ;;            # Hourglass
    *) local chars='/-\|' ;;           # Default simple spinner
  esac

  # Hide cursor
  [[ -t 1 ]] && tput civis

  # Cleanup function to restore cursor and remove spinner
  _spinner_cleanup() {
    [[ -t 1 ]] && tput cnorm # Restore cursor
    [[ -t 1 ]] && tput el    # Clear line
    echo -en "\r${RESET}"
  }

  # Main spinner loop with rainbow effect, live last-log line, and sudo detection
  local rainbow_index=0 tick=0 keepalive_pid=""
  while ps -p "$pid" &>/dev/null; do
    if [[ -z "$keepalive_pid" ]] && ((tick % 5 == 0)) && _has_descendant_named "$pid" sudo; then
      _spinner_pause_for_sudo "$pid" "$msg"
      keepalive_pid="$(_spinner_start_sudo_keepalive "$pid")"
    fi
    local cols max
    if [[ -t 1 && -n "$logfile" ]]; then
      cols=$(tput cols 2>/dev/null || echo 80)
      max=$((cols - ${#msg} - 6))
      ((max < 10)) && max=10
    fi
    for ((i = 0; i < ${#chars}; i++)); do
      local color=${RAINBOW[$rainbow_index]}
      local line="\r${color}${chars:$i:1}${RESET} ${msg}"
      if [[ -t 1 && -n "$logfile" ]]; then
        local last
        last="$(_sanitize_log_line "$(tail -n 1 "$logfile" 2>/dev/null)" "$max")"
        [[ -n "$last" ]] && line="\r\033[K${color}${chars:$i:1}${RESET} ${msg} ${DIM}— ${last}${RESET}"
      fi
      echo -en "$line"
      sleep $delay
      rainbow_index=$(((rainbow_index + 1) % ${#RAINBOW[@]}))
    done
    tick=$((tick + 1))
  done

  [[ -n "$keepalive_pid" ]] && kill "$keepalive_pid" 2>/dev/null
  _spinner_cleanup
}

# Run <cmd> in the background with stdout+stderr captured to a fresh temp file
# exposed as the global RUN_LOG, while a spinner animates and live-tails it.
# Callers read $RUN_LOG afterwards (e.g. to grep for errors) and `rm -f` it.
# Returns <cmd>'s exit code.
run_with_spinner() {
  local cmd="$1"            # Command to run
  local style="$2"          # Spinner style
  local msg="$3"            # Custom message
  local show_exit="${4:-0}" # Print Success!/Failed! when 1

  # RUN_LOG is global on purpose: callers in dot-update read it after we return.
  # shellcheck disable=SC2034  # read by callers in a separate file
  RUN_LOG="$(mktemp)" # owned by this runner, removed by the caller
  # stdin is detached to /dev/null so an unattended step can never block on an
  # interactive prompt (e.g. SDKMAN's "Use prescribed default version(s)?"): the
  # child reads EOF and proceeds with defaults instead of hanging the whole run.
  eval "$cmd" >"$RUN_LOG" 2>&1 </dev/null &
  local pid=$!

  spinner "$pid" "${style:-0}" "${msg:-Working...}" "$RUN_LOG"

  wait "$pid"
  local exit_status=$?

  echo -en "\r\033[K"
  [[ -t 1 ]] && tput cnorm

  if [ "$show_exit" -eq 1 ]; then
    if [ $exit_status -eq 0 ]; then
      log_success "Success!"
    else
      log_error "Failed!"
    fi
  fi

  return $exit_status
}

########################################################
# Spinner helpers
########################################################

# Clean a raw log line for inline display: strip ANSI CSI sequences, turn
# tabs/CRs into spaces, drop other control bytes, squeeze spaces, trim ends, and
# truncate to <maxlen> columns. Pure: same input -> same output, no side effects.
_sanitize_log_line() {
  local text="$1" maxlen="${2:-80}" esc
  esc=$(printf '\033')
  text=$(printf '%s' "$text" |
    sed "s/${esc}\[[0-9;]*[a-zA-Z]//g" |
    tr '\r\t' '  ' |
    tr -d '\a' |
    tr -s ' ')
  # trim leading/trailing whitespace left by the squeeze
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  [[ ${#text} -gt $maxlen ]] && text="${text:0:maxlen}"
  printf '%s' "$text"
}

# Print every descendant PID of <pid>, depth-first. Used to detect helpers
# (e.g. sudo) that a backgrounded command spawns.
_descendant_pids() {
  local pid="$1" child
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    printf '%s\n' "$child"
    _descendant_pids "$child"
  done
}

# Exit 0 if any descendant of <pid> has a command name ending in <name>.
_has_descendant_named() {
  local pid="$1" name="$2" d comm
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    comm="$(ps -o comm= -p "$d" 2>/dev/null)"
    case "$comm" in
      *"$name") return 0 ;;
    esac
  done < <(_descendant_pids "$pid")
  return 1
}

# Pause the spinner and surface a clear prompt while a sudo child waits for the
# password. sudo writes its own "Password:" line to the tty beneath this banner.
# Blocks until the sudo descendant exits or the command finishes.
_spinner_pause_for_sudo() {
  local pid="$1" msg="$2"
  [[ -t 1 ]] && tput cnorm
  echo -en "\r\033[K"
  printf "  %b🔒 %s needs your password%b\n" "${BOLD}${YELLOW}" "$msg" "$RESET"
  while ps -p "$pid" &>/dev/null && _has_descendant_named "$pid" sudo; do
    sleep 0.3
  done
  [[ -t 1 ]] && tput civis
}

# After the first sudo succeeds, refresh the timestamp every 30s while <pid> runs
# so further sudo calls in the same run don't re-prompt. `sudo -n` never prompts.
# Prints the background refresher PID for the caller to kill on cleanup. The
# >/dev/null redirect detaches the loop's stdout so the $() caller gets EOF and
# does not block on the long-lived background job.
_spinner_start_sudo_keepalive() {
  local pid="$1"
  { while kill -0 "$pid" 2>/dev/null; do
    sudo -n -v 2>/dev/null || true
    sleep 30
  done; } </dev/null >/dev/null 2>&1 &
  printf '%s' "$!"
}

# Print a "[n/total] label" step header: dim counter, bold label.
fmt_step_header() {
  local n="$1" total="$2" label="$3"
  printf "\n%b[%s/%s]%b %b%s%b\n" "$DIM" "$n" "$total" "$RESET" "$BOLD" "$label" "$RESET"
}

########################################################
# Profile / machine config
########################################################
# State lives under $XDG_CONFIG_HOME/dotfiles/ — never committed.
# profile: a single word (personal|work). config: key=value lines.

_dot_state_dir() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"; }

# Print the active profile, defaulting to personal when unset/invalid.
dot_profile() {
  local file p="personal"
  file="$(_dot_state_dir)/profile"
  if [[ -f "$file" ]]; then
    p="$(tr -d '[:space:]' <"$file")"
  fi
  [[ "$p" == "personal" || "$p" == "work" ]] || p="personal"
  printf '%s\n' "$p"
}

# Persist the active profile. Rejects anything but personal|work.
dot_set_profile() {
  local name="${1:-}" dir
  if [[ "$name" != "personal" && "$name" != "work" ]]; then
    log_error "Invalid profile: '$name' (must be 'personal' or 'work')"
    return 1
  fi
  dir="$(_dot_state_dir)"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  printf '%s\n' "$name" >"$dir/profile"
}

# Print the value for a config key. Prints one (possibly empty) line when the
# file exists; prints nothing when the file is absent. Command-substitution
# callers (`$(dot_config key)`) see "" in all absent cases. Always exits 0.
dot_config() {
  local key="${1:-}" file line value=""
  file="$(_dot_state_dir)/config"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" == "$key="* ]] && value="${line#*=}"
  done <"$file"
  printf '%s\n' "$value"
}

# Upsert key=value: replace the existing key= line in place, else append.
dot_set_config() {
  local key="${1:-}" value="${2:-}" dir file tmp line found=0
  dir="$(_dot_state_dir)"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  file="$dir/config"
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == "$key="* ]]; then
        printf '%s=%s\n' "$key" "$value"
        found=1
      else
        printf '%s\n' "$line"
      fi
    done <"$file"
  fi >"$tmp"
  [[ "$found" -eq 0 ]] && printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv "$tmp" "$file"
}

########################################################
# Homebrew profile bundles
########################################################

# Print the Brewfile paths for the active (or given) profile: core, then the
# profile-specific file if it exists.
dot_brewfiles() {
  local profile="${1:-$(dot_profile)}" dir
  dir="${DOTFILES:?DOTFILES must be set}/brew"
  [[ -f "$dir/Brewfile.core" ]] && printf '%s\n' "$dir/Brewfile.core"
  [[ -f "$dir/Brewfile.$profile" ]] && printf '%s\n' "$dir/Brewfile.$profile"
  return 0
}

# Resolve the Docker runtime: the docker_runtime config override, else the
# profile default (work -> rancher, otherwise docker-desktop).
dot_docker_runtime() {
  local runtime
  runtime="$(dot_config docker_runtime)"
  if [[ -z "$runtime" ]]; then
    case "$(dot_profile)" in
      work) runtime="rancher" ;;
      *) runtime="docker-desktop" ;;
    esac
  fi
  printf '%s\n' "$runtime"
}

# Print the brew-bundle entry/entries for a Docker runtime; return 1 if unknown.
dot_docker_runtime_entries() {
  case "${1:-}" in
    docker-desktop) printf "%s\n" "cask 'docker-desktop'" ;;
    rancher) printf "%s\n" "cask 'rancher'" ;;
    colima) printf "%s\n%s\n" "brew 'colima'" "brew 'docker'" ;;
    *) return 1 ;;
  esac
}

########################################################
# Soft-fail step runner
########################################################
# Run named steps non-fatally and tally the outcomes. A step command returns
# 0 (ok), STEP_SKIP_CODE (skipped), or anything else (failed). The runner never
# propagates a failure, so one bad step never aborts the rest.

STEP_SKIP_CODE=78
# Initialized at source time so `step` is safe even before an explicit step_init.
_step_ok=0
_step_skipped=()
_step_failed=()
_step_timings=() # "<elapsed_seconds>|<label>" per step that actually ran

step_init() {
  _step_ok=0
  _step_skipped=()
  _step_failed=()
  _step_timings=()
}

# step <label> <command> [args...]
step() {
  local label="$1"
  shift
  # Dry-run: list the step as "would run" and tally it ok — skip guards are NOT evaluated.
  if [[ "${STEP_DRY_RUN:-0}" == "1" ]]; then
    log_info "would run: $label"
    _step_ok=$((_step_ok + 1))
    return 0
  fi
  # $SECONDS is a bash builtin (3.2+); the delta is monotonic and immune to clock changes.
  local start=$SECONDS
  local rc=0
  "$@" || rc=$?
  local elapsed=$((SECONDS - start))
  if [[ "$rc" -eq 0 ]]; then
    _step_ok=$((_step_ok + 1))
  elif [[ "$rc" -eq "$STEP_SKIP_CODE" ]]; then
    _step_skipped+=("$label")
  else
    _step_failed+=("$label")
  fi
  _step_timings+=("$elapsed|$label")
  return 0
}

# fmt_duration <seconds> -> compact human string: 5 -> "5s", 90 -> "1m30s",
# 17794 -> "4h56m34s". Pure: same input -> same output, no side effects.
fmt_duration() {
  local total="$1" h m s out=""
  h=$((total / 3600))
  m=$(((total % 3600) / 60))
  s=$((total % 60))
  [[ $h -gt 0 ]] && out+="${h}h"
  [[ $h -gt 0 || $m -gt 0 ]] && out+="${m}m"
  out+="${s}s"
  printf '%s' "$out"
}

# step_summary — print the tally and a per-step timing breakdown (longest first,
# so a slow step is obvious); return 1 if any step failed.
step_summary() {
  echo
  fmt_title_underline "Summary"
  printf "  %b%d ok%b  %b%d skipped%b  %b%d failed%b\n" \
    "$GREEN" "$_step_ok" "$RESET" \
    "$YELLOW" "${#_step_skipped[@]}" "$RESET" \
    "$RED" "${#_step_failed[@]}" "$RESET"
  local s
  for s in "${_step_skipped[@]+"${_step_skipped[@]}"}"; do
    printf "    %b⊘ %s%b\n" "$YELLOW" "$s" "$RESET"
  done
  for s in "${_step_failed[@]+"${_step_failed[@]}"}"; do
    printf "    %b✗ %s%b\n" "$RED" "$s" "$RESET"
  done
  if [[ "${#_step_timings[@]}" -gt 0 ]]; then
    printf "  %bTimings (longest first)%b\n" "$BOLD" "$RESET"
    local elapsed lbl
    while IFS='|' read -r elapsed lbl; do
      [[ -n "$elapsed" ]] || continue
      printf "    %b%8s%b  %s\n" "$DIM" "$(fmt_duration "$elapsed")" "$RESET" "$lbl"
    done < <(printf '%s\n' "${_step_timings[@]}" | sort -rn -t'|' -k1)
  fi
  [[ "${#_step_failed[@]}" -eq 0 ]]
}

setup_colors
