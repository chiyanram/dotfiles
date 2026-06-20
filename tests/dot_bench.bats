setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  BENCH="$REPO/bin/dot-bench"
}

@test "dot-bench has a Description line for auto-discovery" {
  run sed -n '2p' "$BENCH"
  [[ "$output" == "# Description:"* ]]
}

@test "dot-bench runs and reports a median in ms" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run bash "$BENCH"
  [ "$status" -eq 0 ]
  [[ "$output" =~ median:\ [0-9]+\ ms ]]
}

@test "dot-bench --help exits 0 and explains usage" {
  run bash "$BENCH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}
