load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "backup creates an archive of a real (non-symlink) config file" {
  # Place a real file where a home dotfile would be linked
  printf 'real contents\n' >"$HOME/.demorc"
  run "$DOT" backup -d "$SANDBOX/bk"
  [ "$status" -eq 0 ]
  # exactly one archive was produced
  run bash -c "ls \"$SANDBOX/bk\"/dotfiles_backup_*.tar.gz | wc -l"
  [ "$output" -eq 1 ]
}

@test "backup leaves no temp files behind (isolated TMPDIR)" {
  printf 'real contents\n' >"$HOME/.demorc"
  export TMPDIR="$SANDBOX/tmp"
  mkdir -p "$TMPDIR"
  "$DOT" backup -d "$SANDBOX/bk" >/dev/null 2>&1
  # cmd_backup's mktemp lands in TMPDIR; after the run it must be empty again.
  run bash -c "ls -A \"$TMPDIR\" | wc -l"
  [ "$output" -eq 0 ]
}

@test "backup with no real files to back up still exits 0" {
  run "$DOT" backup -d "$SANDBOX/bk"
  [ "$status" -eq 0 ]
}
