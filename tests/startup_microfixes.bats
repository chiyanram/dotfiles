setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  ZSHRC="$REPO/home/.zshrc"
  STARSHIP="$REPO/config/starship/starship.toml"
}

@test "starship kubernetes gates on KUBECONFIG env var" {
  grep -q "detect_env_vars = \['KUBECONFIG'\]" "$STARSHIP"
}

@test ".zshrc uses HOMEBREW_PREFIX for FPATH" {
  grep -q 'HOMEBREW_PREFIX' "$ZSHRC"
}

@test ".zshrc no longer subprocesses brew --prefix" {
  ! grep -q 'brew --prefix' "$ZSHRC"
}
