load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "link all symlinks a config package into XDG_CONFIG_HOME" {
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ]
  [ "$(readlink "$XDG_CONFIG_HOME/demo")" = "$DOTFILES/config/demo" ]
}

@test "link all symlinks a home file into HOME" {
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ -L "$HOME/.demorc" ]
  [ "$(readlink "$HOME/.demorc")" = "$DOTFILES/home/.demorc" ]
}

@test "link all is idempotent (second run is a clean no-op)" {
  run "$DOT" link all
  [ "$status" -eq 0 ]
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ]
  [ "$(readlink "$XDG_CONFIG_HOME/demo")" = "$DOTFILES/config/demo" ]
  [ -L "$HOME/.demorc" ]
  [ "$(readlink "$HOME/.demorc")" = "$DOTFILES/home/.demorc" ]
}

@test "unlink all removes the symlinks it created" {
  "$DOT" link all
  run "$DOT" unlink all
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/demo" ]
  [ ! -e "$HOME/.demorc" ]
}
