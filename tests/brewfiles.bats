setup() { REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"; }

@test "brew Brewfiles are valid ruby syntax" {
  command -v ruby >/dev/null || skip "ruby not installed"
  local f
  for f in "$REPO"/brew/Brewfile.*; do
    run ruby -c "$f"
    [ "$status" -eq 0 ]
  done
}
