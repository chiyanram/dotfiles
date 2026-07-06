setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
}

# Strip ANSI color escapes so assertions see plain text.
strip_ansi() {
  local esc
  esc=$(printf '\033')
  sed "s/${esc}\[[0-9;]*m//g"
}

# Fake nvim that emits 20 numbered lines then fails, like a crashed
# `nvim --headless '+Lazy! sync' +qa`.
make_failing_nvim() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/nvim" <<'EOF'
#!/bin/bash
i=1
while [ "$i" -le 20 ]; do
  printf 'nvim-log-line %02d\n' "$i"
  i=$((i + 1))
done
echo 'E5108: Error executing lua boom' >&2
exit 1
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/nvim"
}

# Issue #18: a failing nvim step printed a bare "✖ Error occurred during
# Neovim plugin update" and deleted the captured log — no diagnostic at all.
@test "dot update nvim failure shows the tail of the captured log, not a bare error" {
  make_failing_nvim
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$REPO/bin/dot-update" nvim
  [ "$status" -eq 1 ]
  plain="$(printf '%s\n' "$output" | strip_ansi)"
  [[ "$plain" == *"Error occurred during Neovim plugin update"* ]]
  # The actual failure output is surfaced by default (no -v needed)...
  [[ "$plain" == *"E5108: Error executing lua boom"* ]]
  [[ "$plain" == *"nvim-log-line 20"* ]]
  # ...but as a tail: with 21 log lines, line 01 is older than the last 15.
  [[ "$plain" != *"nvim-log-line 01"* ]]
}

@test "dot update nvim failure keeps the full log and prints its path" {
  make_failing_nvim
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$REPO/bin/dot-update" nvim
  [ "$status" -eq 1 ]
  plain="$(printf '%s\n' "$output" | strip_ansi)"
  log_path="$(printf '%s\n' "$plain" | grep -F 'Full log kept at: ' | sed 's/.*Full log kept at: //')"
  [ -n "$log_path" ]
  [ -f "$log_path" ]
  # The kept log holds everything, including lines the tail cut off.
  grep -q 'nvim-log-line 01' "$log_path"
  rm -f "$log_path"
}

@test "dot update -v nvim failure shows the full captured log" {
  make_failing_nvim
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$REPO/bin/dot-update" -v nvim
  [ "$status" -eq 1 ]
  plain="$(printf '%s\n' "$output" | strip_ansi)"
  [[ "$plain" == *"nvim-log-line 01"* ]]
  [[ "$plain" == *"E5108: Error executing lua boom"* ]]
}
