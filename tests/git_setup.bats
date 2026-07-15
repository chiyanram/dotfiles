setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks so include paths match
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export DOTFILES="$REPO"
  export TERM=dumb
  # Make git use a clean global config (the committed one) under XDG, so
  # `github.user`'s default-read (no -f, relies on the include chain) is
  # deterministic — an ambient XDG_CONFIG_HOME/git/config on the host would
  # otherwise leak through instead.
  export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
  mkdir -p "$XDG_CONFIG_HOME/git"
  cp "$REPO/config/git/config" "$GIT_CONFIG_GLOBAL"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "setup's source no longer prompts for name/email (#158)" {
  # bash's `read -p` suppresses the prompt text entirely when stdin isn't a
  # terminal (as under `run`/piped input in tests), so assert on the source
  # instead of captured output.
  run sed -n '/^setup_git()/,/^}/p' "$REPO/bin/dot-git"
  [[ "$output" != *'read -rp "Name'* ]]
  [[ "$output" != *'read -rp "Email'* ]]
  [[ "$output" == *'read -rp "Github username'* ]]
}

@test "setup writes github.user and credential.helper, never a [user] block" {
  run bash -c "printf 'octocat\n' | '$REPO/bin/dot-git' setup"
  [ "$status" -eq 0 ]
  run git config -f "$HOME/.gitconfig-local" github.user
  [ "$output" = "octocat" ]
  run git config -f "$HOME/.gitconfig-local" credential.helper
  [ "$output" = "osxkeychain" ]
  run git config -f "$HOME/.gitconfig-local" --get-regexp '^user\.'
  [ "$status" -ne 0 ] # no [user] block written at all
}

@test "setup is idempotent — re-run keeps the existing github.user as the default" {
  bash -c "printf 'octocat\n' | '$REPO/bin/dot-git' setup" >/dev/null
  run bash -c "printf '\n' | '$REPO/bin/dot-git' setup"
  [ "$status" -eq 0 ]
  run git config -f "$HOME/.gitconfig-local" github.user
  [ "$output" = "octocat" ]
}
