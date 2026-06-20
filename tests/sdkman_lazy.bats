setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  source "$REPO/bin/lib/sdkman-lazy.sh"
  FAKE="$BATS_TEST_TMPDIR/sdkman"
}

@test "candidate bins lists current/bin dirs for each candidate" {
  mkdir -p "$FAKE/candidates/java/current/bin" "$FAKE/candidates/gradle/current/bin"
  run _sdkman_candidate_bins "$FAKE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$FAKE/candidates/java/current/bin"* ]]
  [[ "$output" == *"$FAKE/candidates/gradle/current/bin"* ]]
}

@test "candidate bins emits nothing when no candidates exist" {
  mkdir -p "$FAKE/candidates"
  run _sdkman_candidate_bins "$FAKE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "candidate bins emits nothing when dir is absent" {
  run _sdkman_candidate_bins "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "candidate bins skips a candidate with no current/bin" {
  mkdir -p "$FAKE/candidates/java/current/bin"
  mkdir -p "$FAKE/candidates/broken/current"
  run _sdkman_candidate_bins "$FAKE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$FAKE/candidates/java/current/bin"* ]]
  [[ "$output" != *"broken"* ]]
}

@test "has-rc is true when .sdkmanrc is present" {
  cd "$BATS_TEST_TMPDIR"
  touch .sdkmanrc
  run _sdkman_has_rc
  [ "$status" -eq 0 ]
}

@test "has-rc is false when .sdkmanrc is absent" {
  cd "$BATS_TEST_TMPDIR"
  rm -f .sdkmanrc
  run _sdkman_has_rc
  [ "$status" -ne 0 ]
}
