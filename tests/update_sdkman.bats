setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
}

# Regression test for the bug where `export sdkman_auto_answer=true` ran BEFORE
# sourcing sdkman-init.sh. The init re-sources ~/.sdkman/etc/config (which ships
# sdkman_auto_answer=false), clobbering the export back to false — so `sdk update`
# prompted interactively ("Use prescribed default versions? Y/N"). The fix sets
# the var AFTER the source so it survives.
@test "dot update sdkman runs sdk with auto_answer=true despite etc/config default" {
  local fake="$BATS_TEST_TMPDIR/sdkman"
  mkdir -p "$fake/bin"
  local marker="$BATS_TEST_TMPDIR/marker"
  # fake init mimics etc/config setting auto_answer=false, then defines `sdk`
  # to record the value it actually sees when invoked.
  cat >"$fake/bin/sdkman-init.sh" <<EOF
sdkman_auto_answer=false
sdk() { printf 'auto_answer=%s\n' "\$sdkman_auto_answer" >>"$marker"; }
EOF

  run env SDKMAN_DIR="$fake" bash "$REPO/bin/dot-update" sdkman
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
  grep -q 'auto_answer=true' "$marker"
  ! grep -q 'auto_answer=false' "$marker"
}
