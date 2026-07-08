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

@test "unlink all writes a manifest and restore recreates the symlinks it removed" {
  "$DOT" link all
  rm -f "$STATE"/manifest-*.tsv # isolate: only the unlink step's manifest matters here

  run "$DOT" unlink all
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/demo" ]
  [ ! -e "$HOME/.demorc" ]
  [ -n "$(manifests)" ] # a manifest was recorded for the unlink

  run "$DOT" restore
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ]
  [ "$(readlink "$XDG_CONFIG_HOME/demo")" = "$DOTFILES/config/demo" ]
  [ -L "$HOME/.demorc" ]
  [ "$(readlink "$HOME/.demorc")" = "$DOTFILES/home/.demorc" ]
}

@test "link <pkg> writes a manifest and restore undoes it (previously silent, un-undoable)" {
  run "$DOT" link demo
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ]
  [ -n "$(manifests)" ]

  run "$DOT" restore
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/demo" ]
}

@test "link <pkg> -b backs up a real file then links; restore puts the original back" {
  mkdir -p "$XDG_CONFIG_HOME/demo"
  printf 'my real config\n' >"$XDG_CONFIG_HOME/demo/demo.conf"
  run "$DOT" link demo -b
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ]

  run "$DOT" restore
  [ "$status" -eq 0 ]
  [ ! -L "$XDG_CONFIG_HOME/demo" ]
  [ "$(cat "$XDG_CONFIG_HOME/demo/demo.conf")" = "my real config" ]
}

@test "unlink <pkg> writes a manifest and restore recreates the symlink" {
  "$DOT" link demo
  rm -f "$STATE"/manifest-*.tsv # isolate: only the unlink step's manifest matters here

  run "$DOT" unlink demo
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/demo" ]
  [ -n "$(manifests)" ]

  run "$DOT" restore
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ]
  [ "$(readlink "$XDG_CONFIG_HOME/demo")" = "$DOTFILES/config/demo" ]
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
