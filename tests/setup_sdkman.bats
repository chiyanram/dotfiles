load test_helper

setup() {
  SETUP="$BATS_TEST_DIRNAME/../setup.sh"
  FAKE="$BATS_TEST_TMPDIR/sdkman"
  MARKER="$BATS_TEST_TMPDIR/marker"
  mkdir -p "$FAKE/bin"
}

# setup.sh runs its whole life under system bash 3.2 with `set -Eeuo pipefail`.
# sdkman-init.sh cannot be sourced into that process: it expands unset vars
# (line 20: `[ -z "$SDKMAN_CANDIDATES_API" ]` — fatal under set -u, and the
# error aborts the whole script, not just the step) and its helpers use
# bash-4-only syntax (${var^^}). The sdk phase must run in a PATH-bash
# subprocess instead, like dot-update does.
@test "run_sdk survives an init script that is fatal to source under set -u" {
  cat >"$FAKE/bin/sdkman-init.sh" <<EOF
# mirrors real sdkman-init.sh line 20: unguarded expansion, fatal under set -u
if [ -z "\$SDKMAN_CANDIDATES_API" ]; then
  export SDKMAN_CANDIDATES_API="https://api.sdkman.io/2"
fi
sdk() { printf 'sdk %s\n' "\$*" >>"$MARKER"; }
EOF

  run env -u SDKMAN_CANDIDATES_API SDKMAN_DIR="$FAKE" /bin/bash -c \
    "set -Eeuo pipefail; source '$SETUP'; run_sdk install java; echo ALIVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *ALIVE* ]]
  grep -q '^sdk install java$' "$MARKER"
}

@test "run_sdk passes multi-word arguments through to sdk" {
  cat >"$FAKE/bin/sdkman-init.sh" <<EOF
sdk() { printf 'sdk %s\n' "\$*" >>"$MARKER"; }
EOF

  run env SDKMAN_DIR="$FAKE" /bin/bash -c \
    "set -Eeuo pipefail; source '$SETUP'; run_sdk install java 21.0.7-tem"
  [ "$status" -eq 0 ]
  grep -q '^sdk install java 21.0.7-tem$' "$MARKER"
}
