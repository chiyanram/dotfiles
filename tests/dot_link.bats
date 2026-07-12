load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "bare 'dot link' errors with usage, not an unbound-variable crash" {
  run "$DOT" link
  [ "$status" -ne 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" == *"--status"* || "$output" == *"Usage"* || "$output" == *"usage"* ]]
}

@test "bare 'dot unlink' errors with usage, not an unbound-variable crash" {
  run "$DOT" unlink
  [ "$status" -ne 0 ]
  [[ "$output" != *"unbound variable"* ]]
}

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

@test "unlink all leaves a foreign symlink alone (not ours to remove)" {
  ln -s /somewhere/else "$XDG_CONFIG_HOME/demo"
  run "$DOT" unlink all
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ]
  [ "$(readlink "$XDG_CONFIG_HOME/demo")" = "/somewhere/else" ]
  [[ "$output" == *"not ours"* ]]
}

@test "unlink <pkg> leaves a real file alone and warns" {
  printf 'not a symlink\n' >"$XDG_CONFIG_HOME/demo"
  run "$DOT" unlink demo
  [ "$status" -eq 0 ]
  [ ! -L "$XDG_CONFIG_HOME/demo" ]
  [ "$(cat "$XDG_CONFIG_HOME/demo")" = "not a symlink" ]
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

@test "link --adopt imports a real file into the repo, then links to it" {
  printf 'machine-specific config\n' >"$HOME/.demorc" # repo has 'demo home rc'
  run "$DOT" link all --adopt
  [ "$status" -eq 0 ]
  [ -L "$HOME/.demorc" ]
  [ "$(readlink "$HOME/.demorc")" = "$DOTFILES/home/.demorc" ]
  # the repo now holds the machine's version, and the link reads it back
  [ "$(cat "$DOTFILES/home/.demorc")" = "machine-specific config" ]
  [ "$(cat "$HOME/.demorc")" = "machine-specific config" ]
}

# managed_targets is the single enumerator of managed files (#44); the optional
# kind argument lets each consumer take just the slice it acts on.
@test "managed_targets config emits only config packages" {
  run bash -c "source '$DOTFILES/bin/lib/links.sh' && managed_targets config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"config/demo"* ]]
  [[ "$output" != *".demorc"* ]]
}

@test "managed_targets home emits only home files" {
  run bash -c "source '$DOTFILES/bin/lib/links.sh' && managed_targets home"
  [ "$status" -eq 0 ]
  [[ "$output" == *".demorc"* ]]
  [[ "$output" != *"config/demo"* ]]
}

@test "managed_targets rejects an unknown kind" {
  run bash -c "source '$DOTFILES/bin/lib/links.sh' && managed_targets bogus"
  [ "$status" -ne 0 ]
}

@test "link -b backs up a real file to a pid-suffixed name, then links (#118)" {
  printf 'real config\n' >"$XDG_CONFIG_HOME/demo"
  run "$DOT" link demo -b
  [ "$status" -eq 0 ]
  [ -L "$XDG_CONFIG_HOME/demo" ] # now a symlink to the repo
  local bak
  bak="$(ls "$XDG_CONFIG_HOME/"demo.backup.* 2>/dev/null | head -1)"
  [ -n "$bak" ]
  [ "$(cat "$bak")" = "real config" ] # original content preserved
  # …backup.<ts>-<pid>: the '_' in the timestamp means any '-<digit>' is the pid.
  [[ "$bak" == *.backup.*-[0-9]* ]]
}
