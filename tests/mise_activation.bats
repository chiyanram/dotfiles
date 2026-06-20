setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  ZSHRC="$REPO/home/.zshrc"
  BREWFILE="$REPO/brew/Brewfile.core"
}

@test ".zshrc activates mise" {
  grep -q 'mise activate zsh' "$ZSHRC"
}

@test ".zshrc guards mise activation on command -v" {
  grep -q 'command -v mise' "$ZSHRC"
}

@test ".zshrc no longer evals fnm" {
  ! grep -q 'fnm env' "$ZSHRC"
}

@test ".zshrc no longer inits pyenv" {
  ! grep -q 'pyenv init' "$ZSHRC"
}

@test "Brewfile.core installs mise" {
  grep -qE "^brew 'mise'" "$BREWFILE"
}

@test "Brewfile.core no longer installs fnm" {
  ! grep -qE "^brew 'fnm'" "$BREWFILE"
}
