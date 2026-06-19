setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  source "$REPO/bin/lib/common.sh"
}

@test "_sanitize_log_line strips ANSI and normalizes whitespace" {
  local esc tab
  esc=$(printf '\033')
  tab=$(printf '\t')
  run _sanitize_log_line "${esc}[1;32m==>${esc}[0m Upgrading${tab}pkg   1 -> 2" 80
  [ "$status" -eq 0 ]
  [ "$output" = "==> Upgrading pkg 1 -> 2" ]
}

@test "_sanitize_log_line truncates to maxlen" {
  run _sanitize_log_line "abcdefghijklmnopqrstuvwxyz" 10
  [ "$status" -eq 0 ]
  [ "$output" = "abcdefghij" ]
}

@test "_sanitize_log_line trims leading and trailing whitespace" {
  run _sanitize_log_line "   foo   bar   " 80
  [ "$status" -eq 0 ]
  [ "$output" = "foo bar" ]
}

@test "_sanitize_log_line on empty input yields empty" {
  run _sanitize_log_line "" 80
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "_has_descendant_named finds a named descendant" {
  local me=$BASHPID
  sleep 30 &
  local child=$!
  run _has_descendant_named "$me" sleep
  kill "$child" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "_has_descendant_named returns nonzero when no match" {
  run _has_descendant_named "$BASHPID" no_such_proc_xyz
  [ "$status" -ne 0 ]
}

@test "fmt_step_header renders [n/N] and label" {
  run fmt_step_header 2 5 "Homebrew packages"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[2/5]"* ]]
  [[ "$output" == *"Homebrew packages"* ]]
}

@test "_spinner_start_sudo_keepalive returns a live background pid" {
  sleep 5 &
  local target=$!
  local ka
  ka="$(_spinner_start_sudo_keepalive "$target")"
  [[ "$ka" =~ ^[0-9]+$ ]]
  kill -0 "$ka" 2>/dev/null
  kill "$ka" "$target" 2>/dev/null || true
}
