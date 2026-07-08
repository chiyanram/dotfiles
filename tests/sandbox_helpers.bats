load test_helper

# #71: teardown_sandbox's bare `[[ cond ]] && rm -rf ...` is its last statement.
# When the condition is false (no sandbox was ever created), the `&&` short-
# circuits, the compound statement returns non-zero, and — since it's the last
# statement in the function — teardown_sandbox itself returns non-zero and
# aborts under set -e (the errexit bats runs teardown functions with). Any bats
# file with a file-level `teardown() { teardown_sandbox; }` and a test that
# never calls setup_sandbox hits this.

@test "teardown_sandbox is a no-op under errexit when no sandbox was created" {
  run bash -c "set -e; source '$BATS_TEST_DIRNAME/test_helper.bash'; unset SANDBOX; teardown_sandbox; echo reached-end"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reached-end"* ]]
}

@test "teardown_sandbox is a no-op under errexit when SANDBOX points at a missing directory" {
  run bash -c "set -e; source '$BATS_TEST_DIRNAME/test_helper.bash'; SANDBOX=/tmp/does-not-exist-$$; teardown_sandbox; echo reached-end"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reached-end"* ]]
}

@test "teardown_sandbox removes an actual sandbox directory" {
  setup_sandbox
  local sandbox_path="$SANDBOX"
  [ -d "$sandbox_path" ]
  teardown_sandbox
  [ ! -d "$sandbox_path" ]
}
