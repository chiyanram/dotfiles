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

@test "run_with_spinner with multi-line output keeps the full log" {
  run_with_spinner "printf 'line one\nline two\nline three\n'" 0 "test"
  grep -q "line three" "$RUN_LOG"
  rm -f "$RUN_LOG"
}

@test "run_with_spinner children read EOF, not the caller's stdin" {
  # Characterizes the non-interactive contract. Feed 'TYPED-INPUT': with stdin
  # detached to /dev/null the child gets EOF and answer stays empty, rather than
  # reading the caller's input as an interactive prompt would.
  run_with_spinner "read -r answer || true; printf 'answer=[%s]\n' \"\$answer\"" 0 "test" <<< 'TYPED-INPUT'
  grep -q 'answer=\[\]' "$RUN_LOG"
  ! grep -q 'TYPED-INPUT' "$RUN_LOG"
  rm -f "$RUN_LOG"
}

@test "run_with_spinner surfaces a sudo banner for every prompt, not just the first" {
  # A step can invoke sudo more than once (brew: once per cask, or a retry after
  # the 5-minute prompt timeout). Every prompt must pause the spinner and print
  # the banner — a once-only pause leaves later prompts erased by the spinner's
  # \r redraw, so the run reads as hung (issue #19's 40m Homebrew step).
  # A symlink named "sudo" fakes the real thing for the descendant scan: comm is
  # the invoked path on macOS ("…/sudo") and its basename on Linux ("sudo").
  ln -s "$(command -v sleep)" "$BATS_TEST_TMPDIR/sudo"
  run run_with_spinner "'$BATS_TEST_TMPDIR/sudo' 3; sleep 1; '$BATS_TEST_TMPDIR/sudo' 3" 0 "test"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'needs your password' <<<"$output")" -ge 2 ]
}
