setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  source "$REPO/bin/lib/common.sh"
}

@test "step records ok and summary returns 0 when nothing failed" {
  step_init
  step "a" true
  run step_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 ok"* ]]
}

@test "step records skip via STEP_SKIP_CODE" {
  step_init
  step "b" bash -c "exit $STEP_SKIP_CODE"
  run step_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 skipped"* ]]
  [[ "$output" == *"b"* ]]
}

@test "step records failure and summary returns non-zero" {
  step_init
  step "c" false
  run step_summary
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 failed"* ]]
  [[ "$output" == *"c"* ]]
}

@test "a failing step does not abort subsequent steps" {
  step_init
  step "x" false
  step "y" true
  [ "$_step_ok" -eq 1 ]
  [ "${#_step_failed[@]}" -eq 1 ]
}

@test "mixed run tallies all three categories" {
  step_init
  step "ok1" true
  step "ok2" true
  step "skip1" bash -c "exit $STEP_SKIP_CODE"
  step "fail1" false
  run step_summary
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 ok"* ]]
  [[ "$output" == *"1 skipped"* ]]
  [[ "$output" == *"1 failed"* ]]
}

@test "dry-run lists steps without executing them" {
  step_init
  export STEP_DRY_RUN=1
  step_init
  local marker="$BATS_TEST_TMPDIR/ran"
  step "should-not-run" touch "$marker"
  [ ! -f "$marker" ]
  run step_summary
  [ "$status" -eq 0 ]
  unset STEP_DRY_RUN
}

@test "step works without an explicit step_init (globals safe under set -u)" {
  # No step_init here — relies on the source-time initialization.
  run step_summary
  [ "$status" -eq 0 ]
}

@test "fmt_duration formats seconds, minutes, and hours" {
  [ "$(fmt_duration 0)" = "0s" ]
  [ "$(fmt_duration 5)" = "5s" ]
  [ "$(fmt_duration 90)" = "1m30s" ]
  [ "$(fmt_duration 3600)" = "1h0m0s" ]
  [ "$(fmt_duration 17794)" = "4h56m34s" ]
}

@test "step_summary reports a timing breakdown for each step that ran" {
  step_init
  step "alpha" true
  step "beta" true
  run step_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"Timings (longest first)"* ]]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "dry-run records no timing breakdown" {
  export STEP_DRY_RUN=1
  step_init
  step "skipme" true
  run step_summary
  unset STEP_DRY_RUN
  [ "$status" -eq 0 ]
  [[ "$output" != *"Timings"* ]]
}
