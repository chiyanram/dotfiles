setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  # Pin DOTFILES so dot-update sources THIS tree's libs, not an inherited one.
  export DOTFILES="$REPO"
  UPDATE="$REPO/bin/dot-update"
}

# Strip ANSI color escapes so assertions see plain text.
strip_ansi() {
  local esc
  esc=$(printf '\033')
  sed "s/${esc}\[[0-9;]*m//g"
}

# Classify a captured `nvim --headless '+Lazy! sync' +qa` run: outcome <exit_status> <log-content>.
outcome() {
  local log
  log="$(mktemp)"
  printf '%s' "$2" >"$log"
  run bash -c "source '$UPDATE'; _nvim_update_outcome '$1' '$log'"
  rm -f "$log"
}

@test "nvim outcome: benign 'Error'/'not installed' text with a zero exit is not a failure" {
  outcome 0 "[editorconfig-vim] fetch | Finished task fetch in 2153ms
Warning: xclip not installed, clipboard sync disabled"
  [ "$output" != "failed" ]
}

@test "nvim outcome: a non-zero exit is a failure" {
  outcome 1 "E5108: Error executing lua boom"
  [ "$output" = "failed" ]
}

@test "nvim outcome: an ANSI red error line is a failure even with a zero exit" {
  red="$(printf '\033[31m')"
  outcome 0 "[foo.nvim] build | ${red}Error: build script exited 1"
  [ "$output" = "failed" ]
}

@test "nvim outcome: a plugin's log task marker is changed, not ok" {
  outcome 0 "[avante.nvim]       log | Running task log
[avante.nvim]       log | 2183acf doc: fix generated doc (8 hours ago)"
  [ "$output" = "changed" ]
}

@test "nvim outcome: a real checkout move is changed, not ok" {
  outcome 0 "[telescope.nvim] checkout | HEAD is now at 427b576 ci: bump actions/checkout from 6 to 7"
  [ "$output" = "changed" ]
}

@test "nvim outcome: no change markers is ok" {
  outcome 0 "[editorconfig-vim] fetch | Finished task fetch in 2153ms
[editorconfig-vim] status | Finished task status in 45ms"
  [ "$output" = "ok" ]
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

# Fake nvim that succeeds (exit 0) but whose chatty output contains benign
# "Error"/"not installed" substrings, like lazy.nvim's real headless log.
make_healthy_noisy_nvim() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/nvim" <<'EOF'
#!/bin/bash
echo '[avante.nvim] docs | Finished task docs in 1ms'
echo '[foo.nvim] build | Warning: xclip not installed, clipboard sync disabled'
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/nvim"
}

# Issue #93: a successful sync with benign "not installed" chatter must not be
# misreported as failed.
@test "dot update nvim success is not misreported as failed on benign log text" {
  make_healthy_noisy_nvim
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$REPO/bin/dot-update" nvim
  [ "$status" -eq 0 ]
  plain="$(printf '%s\n' "$output" | strip_ansi)"
  [[ "$plain" != *"Error occurred during Neovim plugin update"* ]]
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
