setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  DOCTOR="$REPO/bin/dot-doctor"
}

# Source the doctor (guarded so main does not run) and call the pure predicate.
run_status() {
  run bash -c "source '$DOCTOR'; _ssh_github_status '$1' '$2'; echo rc=\$?"
}

@test "ssh status is missing when the key file is absent" {
  run_status "$BATS_TEST_TMPDIR/nope" "false"
  [[ "$output" == *"missing"* ]]
  [[ "$output" == *"rc=0"* ]]
}

@test "ssh status is auth-fail when key exists but auth failed" {
  touch "$BATS_TEST_TMPDIR/key"
  run_status "$BATS_TEST_TMPDIR/key" "false"
  [[ "$output" == *"auth-fail"* ]]
  [[ "$output" == *"rc=1"* ]]
}

@test "ssh status is ok when key exists and auth succeeded" {
  touch "$BATS_TEST_TMPDIR/key"
  run_status "$BATS_TEST_TMPDIR/key" "true"
  [[ "$output" == *"ok"* ]]
  [[ "$output" == *"rc=0"* ]]
}
