setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks so includeIf gitdir matches
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export DOTFILES="$REPO"
  export TERM=dumb
  # Make git use a clean global config (the committed one) under XDG.
  export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
  mkdir -p "$XDG_CONFIG_HOME/git"
  cp "$REPO/config/git/config" "$GIT_CONFIG_GLOBAL"
  # Personal identity (applies everywhere by default).
  git config -f "$HOME/.gitconfig-local" user.email "me@home.test"
  git config -f "$HOME/.gitconfig-local" user.name "Me Personal"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "work identity applies under work_dir, personal applies elsewhere" {
  "$REPO/bin/dot-git" work-identity --work-dir "$SANDBOX/work" --name "Me Work" --email "me@work.test"

  mkdir -p "$SANDBOX/work/proj" "$SANDBOX/personal/proj"
  git -C "$SANDBOX/work/proj" init -q
  git -C "$SANDBOX/personal/proj" init -q

  run git -C "$SANDBOX/work/proj" config user.email
  [ "$output" = "me@work.test" ]
  run git -C "$SANDBOX/personal/proj" config user.email
  [ "$output" = "me@home.test" ]
}

@test "work-identity persists work_dir and is idempotent" {
  "$REPO/bin/dot-git" work-identity --work-dir "$SANDBOX/work" --name "Me Work" --email "me@work.test"
  run cat "$XDG_CONFIG_HOME/dotfiles/config"
  [[ "$output" == *"work_dir=$SANDBOX/work"* ]]
  # second run must not duplicate the includeIf
  "$REPO/bin/dot-git" work-identity --work-dir "$SANDBOX/work" --name "Me Work" --email "me@work.test"
  run bash -c "grep -c includeIf '$HOME/.gitconfig-work-include'"
  [ "$output" -eq 1 ]
}

@test "work-identity with no work_dir errors clearly under EOF stdin" {
  run bash -c "'$REPO/bin/dot-git' work-identity --name N --email e@work.test </dev/null"
  [ "$status" -ne 0 ]
  [[ "$output" == *"work directory is required"* ]]
}

@test "work-identity expands a leading ~ in --work-dir" {
  "$REPO/bin/dot-git" work-identity --work-dir "~/work" --name N --email e@work.test
  run cat "$HOME/.gitconfig-work-include"
  [[ "$output" == *"gitdir:$HOME/work/"* ]]
}

@test "work-identity reuses the persisted work_dir when --work-dir is omitted" {
  "$REPO/bin/dot-git" work-identity --work-dir "$SANDBOX/work" --name N --email e@work.test
  # second run with NO --work-dir should reuse the persisted value
  "$REPO/bin/dot-git" work-identity --name N2 --email e2@work.test
  run cat "$HOME/.gitconfig-work-include"
  [[ "$output" == *"gitdir:$SANDBOX/work/"* ]]
}
