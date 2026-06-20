setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  DOT_TEST="$REPO/bin/dot-test"
}

# Run the predicate in a clean bash with a controlled environment.
run_guard() {
  run bash -c "$1; source '$DOT_TEST'; _smoke_should_skip; echo rc=\$?"
}

@test "smoke is skipped on non-Darwin CI" {
  run_guard "export CI=true; uname() { echo Linux; }; export -f uname"
  [[ "$output" == *"rc=0"* ]]
}

@test "smoke runs on Darwin CI" {
  run_guard "export CI=true; uname() { echo Darwin; }; export -f uname"
  [[ "$output" == *"rc=1"* ]]
}

@test "smoke runs locally when CI is unset" {
  run_guard "unset CI; uname() { echo Darwin; }; export -f uname"
  [[ "$output" == *"rc=1"* ]]
}

@test "smoke runs locally on non-Darwin when CI is unset" {
  run_guard "unset CI; uname() { echo Linux; }; export -f uname"
  [[ "$output" == *"rc=1"* ]]
}
