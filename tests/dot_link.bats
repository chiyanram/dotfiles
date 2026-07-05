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

@test "link all skips an empty config package (no symlink created)" {
  mkdir -p "$DOTFILES/config/emptypkg"
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/emptypkg" ]
}

@test "link all --dry-run previews CREATE for unlinked targets and writes nothing" {
  run "$DOT" link all -n
  [ "$status" -eq 0 ]
  [[ "$output" == *"CREATE"* ]]
  [[ "$output" == *"demo"* ]]
  [[ "$output" == *".demorc"* ]]
  # dry-run must not touch the filesystem
  [ ! -e "$XDG_CONFIG_HOME/demo" ]
  [ ! -e "$HOME/.demorc" ]
}

@test "link all --dry-run shows SKIP when everything is already linked" {
  "$DOT" link all
  run "$DOT" link all -n
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
  [[ "$output" != *"CREATE"* ]]
}

@test "link all --dry-run flags a real file as CONFLICT and exits non-zero" {
  printf 'i am a real file\n' >"$HOME/.demorc"
  run "$DOT" link all -n
  [ "$status" -ne 0 ]
  [[ "$output" == *"CONFLICT"* ]]
  [[ "$output" == *".demorc"* ]]
  # still no mutation — the real file is untouched
  [ ! -L "$HOME/.demorc" ]
  [ "$(cat "$HOME/.demorc")" = "i am a real file" ]
}

@test "link all --dry-run shows REPLACE for a symlink pointing elsewhere" {
  ln -s /somewhere/else "$HOME/.demorc"
  run "$DOT" link all -n
  [ "$status" -eq 0 ]
  [[ "$output" == *"REPLACE"* ]]
}

@test "link all --dry-run -v shows a content diff for a conflicting real file" {
  printf 'live content\n' >"$HOME/.demorc" # repo .demorc says 'demo home rc'
  run "$DOT" link all -n -v
  [ "$status" -ne 0 ]
  [[ "$output" == *"CONFLICT"* ]]
  [[ "$output" == *"live content"* ]]
  [[ "$output" == *"demo home rc"* ]]
}

@test "link all -f replaces a symlink that points elsewhere (routes through the shared classifier)" {
  ln -s /nonexistent/whatever "$HOME/.demorc"
  run "$DOT" link all -f
  [ "$status" -eq 0 ]
  [ -L "$HOME/.demorc" ]
  [ "$(readlink "$HOME/.demorc")" = "$DOTFILES/home/.demorc" ]
}

@test "link all leaves a real file untouched (refuses to clobber, non-fatal)" {
  printf 'real\n' >"$HOME/.demorc"
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.demorc" ]
  [ "$(cat "$HOME/.demorc")" = "real" ]
}

@test "link --status exits 0 when linked, non-zero when the state is broken (CI gate)" {
  "$DOT" link all
  run "$DOT" link --status
  [ "$status" -eq 0 ]

  rm "$HOME/.demorc" # break one link
  run "$DOT" link --status
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 missing"* ]]
}
