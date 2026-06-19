setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
}

@test "dot-update -n all prints [n/N] headers for every step" {
  run bash "$REPO/bin/dot-update" -n all
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1/5]"* ]]
  [[ "$output" == *"[5/5]"* ]]
  [[ "$output" == *"Homebrew"* ]]
}

@test "dot-update -n brew prints a single [1/1] header" {
  run bash "$REPO/bin/dot-update" -n brew
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1/1]"* ]]
  [[ "$output" == *"Homebrew"* ]]
}
