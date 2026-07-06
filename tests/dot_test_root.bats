setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
}

# The gate must always test the tree it lives in. An inherited DOTFILES
# (e.g. exported by .zshenv pointing at the main checkout) must not redirect
# it — that silently lints/tests the wrong checkout (issue #30).
@test "dot-test derives DOTFILES from its own location, ignoring env" {
  local copy="$BATS_TEST_TMPDIR/other-checkout"
  mkdir -p "$copy"
  cp -R "$REPO/bin" "$copy/bin"
  copy="$(cd "$copy" && pwd -P)"

  run bash -c "export DOTFILES='$REPO'; source '$copy/bin/dot-test'; echo \"root=\$DOTFILES\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"root=$copy"* ]]
}

@test "dot-test resolves its own tree when DOTFILES is unset" {
  run bash -c "unset DOTFILES; source '$REPO/bin/dot-test'; echo \"root=\$DOTFILES\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"root=$REPO"* ]]
}
