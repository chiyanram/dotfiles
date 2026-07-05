setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  SANDBOX="$(mktemp -d)"
  export SANDBOX
  # A fake `sdk list java` (pipe table, identifier in the last column) — two Temurin
  # majors with multiple patches, plus a GraalVM row that must be ignored.
  FAKE_LIST="$SANDBOX/sdklist"
  cat >"$FAKE_LIST" <<'EOF'
   Temurin       |     | 26.0.1       | tem     |            | 26.0.1-tem
                 | >>> | 25.0.3       | tem     | installed  | 25.0.3-tem
                 |     | 25.0.2       | tem     |            | 25.0.2-tem
                 |     | 21.0.11      | tem     | installed  | 21.0.11-tem
                 |     | 21.0.10      | tem     |            | 21.0.10-tem
                 |     | 17.0.19      | tem     | installed  | 17.0.19-tem
   GraalVM       |     | 25.0.3       | graal   |            | 25.0.3-graal
EOF
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Source dot-sdkman (main is guarded), mock run_sdk to serve the fake list, and
# call resolve_temurin with the given spec.
resolve() {
  cat >"$SANDBOX/driver.sh" <<DRIVER
source "$REPO/bin/dot-sdkman"
run_sdk() { cat "$FAKE_LIST"; }
resolve_temurin "$1"
DRIVER
  DOTFILES="$REPO" bash "$SANDBOX/driver.sh"
}

@test "resolve_temurin latest picks the newest Temurin build" {
  run resolve latest
  [ "$status" -eq 0 ]
  [ "$output" = "26.0.1-tem" ]
}

@test "resolve_temurin <major> picks the newest patch of that major" {
  run resolve 25
  [ "$output" = "25.0.3-tem" ]
  run resolve 21
  [ "$output" = "21.0.11-tem" ]
  run resolve 17
  [ "$output" = "17.0.19-tem" ]
}

@test "resolve_temurin ignores non-Temurin (graal) builds" {
  run resolve 25
  [[ "$output" != *graal* ]]
}

@test "sdkman_install installs bare candidates and resolved java, sets the default" {
  local calls="$SANDBOX/calls" tc="$SANDBOX/toolchain"
  cat >"$tc" <<'EOF'
# comment ignored
gradle
kotlin

java latest
java 25 default
java 17
EOF
  cat >"$SANDBOX/driver.sh" <<DRIVER
source "$REPO/bin/dot-sdkman"
run_sdk() {
  if [ "\$1" = list ]; then cat "$FAKE_LIST"; return 0; fi
  printf 'sdk %s\n' "\$*" >>"$calls"
}
sdkman_install
DRIVER
  run env DOTFILES="$REPO" SDKMAN_TOOLCHAIN="$tc" bash "$SANDBOX/driver.sh"
  [ "$status" -eq 0 ]
  # bare candidates → default (latest stable), no version
  grep -qx 'sdk install gradle' "$calls"
  grep -qx 'sdk install kotlin' "$calls"
  # java majors → resolved Temurin patch
  grep -qx 'sdk install java 26.0.1-tem' "$calls"
  grep -qx 'sdk install java 25.0.3-tem' "$calls"
  grep -qx 'sdk install java 17.0.19-tem' "$calls"
  # only the 'default'-flagged java is set as default
  grep -qx 'sdk default java 25.0.3-tem' "$calls"
  ! grep -q 'sdk default java 26' "$calls"
}
