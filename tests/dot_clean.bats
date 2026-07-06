load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

# Turn the fixture DOTFILES into a git repo where home/.claude/settings.json
# existed, was linked into $HOME, then was deleted from the repo — the exact
# shape of the ~/.claude dangling-link case (#21). `dot clean`'s repo-derived
# scan can't name the target (the source is gone); only git history can.
setup_deleted_source_dangle() {
  mkdir -p "$DOTFILES/home/.claude" "$HOME/.claude"
  printf '{}\n' >"$DOTFILES/home/.claude/settings.json"
  git -C "$DOTFILES" init -q
  git -C "$DOTFILES" -c user.email=t@t -c user.name=t add -A
  git -C "$DOTFILES" -c user.email=t@t -c user.name=t commit -qm init
  ln -s "$DOTFILES/home/.claude/settings.json" "$HOME/.claude/settings.json"
  git -C "$DOTFILES" rm -q home/.claude/settings.json
  git -C "$DOTFILES" -c user.email=t@t -c user.name=t commit -qm "remove claude"
}

@test "clean removes a dangling link whose repo source was deleted (git-history derived)" {
  setup_deleted_source_dangle
  [ -L "$HOME/.claude/settings.json" ] # dangle exists before
  run "$DOT" clean
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/settings.json" ] && [ ! -L "$HOME/.claude/settings.json" ]
}

@test "clean leaves healthy links and foreign symlinks alone" {
  setup_deleted_source_dangle
  # healthy managed link
  ln -s "$DOTFILES/home/.demorc" "$HOME/.demorc"
  # dangling link that does NOT point into DOTFILES — not ours to remove
  ln -s "$HOME/nonexistent-foreign" "$HOME/.foreignrc"
  run "$DOT" clean
  [ "$status" -eq 0 ]
  [ -L "$HOME/.demorc" ]    # healthy managed link untouched
  [ -L "$HOME/.foreignrc" ] # foreign dangle untouched
}
