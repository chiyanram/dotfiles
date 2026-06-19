setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  source "$REPO/bin/lib/common.sh"
}

@test "run_with_spinner sets RUN_LOG capturing stdout" {
  run_with_spinner "printf 'hello-world\n'" 0 "test"
  [ -n "$RUN_LOG" ]
  [ -f "$RUN_LOG" ]
  grep -q "hello-world" "$RUN_LOG"
  rm -f "$RUN_LOG"
}

@test "run_with_spinner captures stderr too" {
  run_with_spinner "echo oops 1>&2" 0 "test"
  grep -q "oops" "$RUN_LOG"
  rm -f "$RUN_LOG"
}

@test "run_with_spinner returns the command exit code" {
  run run_with_spinner "exit 3" 0 "test"
  [ "$status" -eq 3 ]
}
