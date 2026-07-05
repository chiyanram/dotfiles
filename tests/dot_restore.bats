load test_helper

setup() {
  setup_sandbox
  STATE="$HOME/.local/state/dot"
}
teardown() { teardown_sandbox; }

manifests() { ls "$STATE"/manifest-*.tsv 2>/dev/null; }

@test "link all writes a manifest and restore undoes the created symlinks" {
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ]
  [ -L "$HOME/.demorc" ]
  [ -n "$(manifests)" ] # a manifest was recorded

  run "$DOT" restore
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/demo" ]
  [ ! -e "$HOME/.demorc" ]
  [ -z "$(manifests)" ] # consumed manifest removed
}

@test "restore repoints a symlink that link -f replaced, back to its old target" {
  ln -s /old/target "$HOME/.demorc"
  run "$DOT" link all -f
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.demorc")" = "$DOTFILES/home/.demorc" ]

  run "$DOT" restore
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.demorc")" = "/old/target" ]
}

@test "restore with no manifest reports an error" {
  run "$DOT" restore
  [ "$status" -ne 0 ]
  [[ "$output" == *"No link manifest"* ]]
}

@test "an all-SKIP re-run records no manifest (nothing changed to undo)" {
  "$DOT" link all # creates the links + a manifest
  rm -f "$STATE"/manifest-*.tsv
  run "$DOT" link all # everything already linked → all SKIP
  [ "$status" -eq 0 ]
  [ -z "$(manifests)" ]
}

@test "restore only touches paths that are still symlinks (won't clobber a real file)" {
  "$DOT" link all
  rm "$HOME/.demorc"                     # user removed the link
  printf 'i replaced it\n' >"$HOME/.demorc" # ...with a real file
  run "$DOT" restore
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.demorc" ]
  [ "$(cat "$HOME/.demorc")" = "i replaced it" ]
}

@test "link -b backs up a real file then links; restore puts the original back" {
  printf 'my real config\n' >"$HOME/.demorc"
  run "$DOT" link all -b
  [ "$status" -eq 0 ]
  [ -L "$HOME/.demorc" ]
  [ "$(readlink "$HOME/.demorc")" = "$DOTFILES/home/.demorc" ]
  ls "$HOME"/.demorc.backup.* >/dev/null 2>&1 # a timestamped backup exists

  run "$DOT" restore
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.demorc" ]
  [ "$(cat "$HOME/.demorc")" = "my real config" ] # original restored
}
