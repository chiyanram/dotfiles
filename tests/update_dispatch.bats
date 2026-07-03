setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
}

@test "dot-update -n all prints [n/N] headers for every step" {
  run bash "$REPO/bin/dot-update" -n all
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1/5]"* ]]
  [[ "$output" == *"[2/5]"* ]]
  [[ "$output" == *"[3/5]"* ]]
  [[ "$output" == *"[4/5]"* ]]
  [[ "$output" == *"[5/5]"* ]]
  [[ "$output" == *"Neovim plugins"* ]]
  [[ "$output" == *"Homebrew"* ]]
  [[ "$output" == *"ZSH plugins"* ]]
  [[ "$output" == *"SDKMAN"* ]]
  [[ "$output" == *"dotfiles"* ]]
}

@test "dot-update -n all runs dotfiles first and SDKMAN last" {
  run bash "$REPO/bin/dot-update" -n all
  [ "$status" -eq 0 ]
  first_step="$(printf '%s\n' "$output" | grep -F '[1/5]')"
  last_step="$(printf '%s\n' "$output" | grep -F '[5/5]')"
  [[ "$first_step" == *"dotfiles"* ]]
  [[ "$last_step" == *"SDKMAN"* ]]
}

@test "dot-update -n brew prints a single [1/1] header" {
  run bash "$REPO/bin/dot-update" -n brew
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1/1]"* ]]
  [[ "$output" == *"Homebrew"* ]]
}
