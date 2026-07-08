setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  # Pin DOTFILES so the doctor sources THIS tree's libs, not an inherited one.
  export DOTFILES="$REPO"
  DOCTOR="$REPO/bin/dot-doctor"
}

# Source the doctor (guarded so main does not run) and call the pure predicate.
run_status() {
  run bash -c "source '$DOCTOR'; _ssh_host_status '$1' '$2'; echo rc=\$?"
}

# The pure gate deciding whether doctor runs its GitLab SSH check.
gitlab_gate() {
  run bash -c "source '$DOCTOR'; _gitlab_ssh_check_enabled \"\$@\"" _ "$@"
}

# Classify a captured `ssh -T` output string into true | untrusted | false.
auth_from_output() {
  run bash -c "source '$DOCTOR'; _ssh_auth_from_output \"\$1\"" _ "$1"
}

@test "auth-from-output: github success message is authenticated" {
  auth_from_output "Hi chiyanram! You've successfully authenticated, but GitHub does not provide shell access."
  [ "$output" = "true" ]
}

@test "auth-from-output: gitlab success message is authenticated" {
  auth_from_output "Welcome to GitLab, @chiyanram!"
  [ "$output" = "true" ]
}

@test "auth-from-output: permission denied is auth-fail" {
  auth_from_output "git@gitlab.com: Permission denied (publickey)."
  [ "$output" = "false" ]
}

@test "auth-from-output: host key verification failure is untrusted" {
  auth_from_output "Host key verification failed."
  [ "$output" = "untrusted" ]
}

@test "gitlab ssh check runs when glab is authenticated" {
  gitlab_gate true false
  [ "$status" -eq 0 ]
}

@test "gitlab ssh check runs when a gitlab slot exists" {
  gitlab_gate false true
  [ "$status" -eq 0 ]
}

@test "gitlab ssh check is skipped when neither glab-auth nor a gitlab slot is present" {
  gitlab_gate false false
  [ "$status" -ne 0 ]
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

@test "ssh status is untrusted when the github host key is not in known_hosts" {
  touch "$BATS_TEST_TMPDIR/key"
  run_status "$BATS_TEST_TMPDIR/key" "untrusted"
  [[ "$output" == *"untrusted"* ]]
  [[ "$output" == *"rc=1"* ]]
}
