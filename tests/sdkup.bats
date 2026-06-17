setup() { REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"; }

@test "sdkup --help exits 0 and explains itself" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -c "source '$REPO/home/.zsh_functions'; sdkup --help"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SDKMAN"* ]]
}

@test "sdkup without SDKMAN reports unavailable and returns non-zero" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -c "source '$REPO/home/.zsh_functions'; sdkup"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDKMAN"* ]]
}
