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
