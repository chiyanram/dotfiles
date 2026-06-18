#!/usr/bin/env bats

load test_helper

setup() {
  CFG="$BATS_TEST_TMPDIR/config"
  SETUP="$BATS_TEST_DIRNAME/../setup.sh"
}

@test "configure_sdkman_auto_env flips false to true" {
  printf 'sdkman_auto_answer=false\nsdkman_auto_env=false\n' > "$CFG"
  run bash -c "SDKMAN_CONFIG='$CFG'; source '$SETUP'; configure_sdkman_auto_env"
  [ "$status" -eq 0 ]
  grep -q '^sdkman_auto_env=true$' "$CFG"
}

@test "configure_sdkman_auto_env is idempotent (no duplicate keys)" {
  printf 'sdkman_auto_env=true\n' > "$CFG"
  run bash -c "SDKMAN_CONFIG='$CFG'; source '$SETUP'; configure_sdkman_auto_env"
  [ "$status" -eq 0 ]
  run grep -c '^sdkman_auto_env=' "$CFG"
  [ "$output" -eq 1 ]
}

@test "configure_sdkman_auto_env appends when the key is absent" {
  printf 'sdkman_auto_answer=false\n' > "$CFG"
  run bash -c "SDKMAN_CONFIG='$CFG'; source '$SETUP'; configure_sdkman_auto_env"
  [ "$status" -eq 0 ]
  grep -q '^sdkman_auto_env=true$' "$CFG"
}
