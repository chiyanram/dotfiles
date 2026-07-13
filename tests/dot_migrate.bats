setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  SANDBOX="$(mktemp -d)"
  export SANDBOX
  # DOTFILES here is a throwaway git repo (dot-migrate shells out to `git -C
  # $DOTFILES`), seeded with the real lib/brew.sh so sourcing dot-migrate works.
  DOTFILES="$SANDBOX/dotfiles"
  mkdir -p "$DOTFILES/bin/lib" "$DOTFILES/brew"
  cp "$REPO/bin/lib/common.sh" "$DOTFILES/bin/lib/common.sh"
  cp "$REPO/bin/lib/profile.sh" "$DOTFILES/bin/lib/profile.sh"
  cp "$REPO/bin/lib/brew.sh" "$DOTFILES/bin/lib/brew.sh"
  git -C "$DOTFILES" init -q -b main
  git -C "$DOTFILES" config user.email test@example.com
  git -C "$DOTFILES" config user.name "Test"
  git -C "$DOTFILES" commit -q --allow-empty -m init
  # A local bare "origin" so `git pull --ff-only origin main` succeeds.
  ORIGIN="$SANDBOX/origin.git"
  git init -q --bare "$ORIGIN"
  git -C "$DOTFILES" remote add origin "$ORIGIN"
  git -C "$DOTFILES" push -q origin main

  # Fake DOT: records every invocation (name + args) to $CALLS in order.
  CALLS="$SANDBOX/calls"
  DOT="$SANDBOX/fake-dot"
  cat >"$DOT" <<'EOF'
#!/usr/bin/env bash
printf 'dot %s\n' "$*" >>"$CALLS"
case "$1" in
  doctor) exit "${FAKE_DOT_DOCTOR_EXIT:-0}" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$DOT"
  export DOTFILES DOT CALLS
  export DOT_TEST_DOTFILES="$DOTFILES" # the override dot-migrate's own resolution reads
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# Source dot-migrate (main is guarded) and invoke main, with `brew` faked as
# absent so step 4 takes its "Homebrew not installed" branch deterministically.
_run_migrate() {
  cat >"$SANDBOX/driver.sh" <<DRIVER
source "$REPO/bin/dot-migrate"
command() {
  if [ "\$1" = -v ] && [ "\$2" = brew ]; then return 1; fi
  builtin command "\$@"
}
main "\$@"
DRIVER
  run env DOTFILES="$DOTFILES" DOT="$DOT" CALLS="$CALLS" \
    FAKE_DOT_DOCTOR_EXIT="${FAKE_DOT_DOCTOR_EXIT:-0}" bash "$SANDBOX/driver.sh" "$@"
}

@test "dot-migrate has a Description line for auto-discovery" {
  run sed -n '2p' "$REPO/bin/dot-migrate"
  [[ "$output" == "# Description:"* ]]
}

@test "sourcing dot-migrate does not execute main (guard is effective)" {
  run env DOTFILES="$DOTFILES" DOT="$DOT" bash -c "source '$REPO/bin/dot-migrate'; echo sourced-ok"
  [ "$status" -eq 0 ]
  [ "$output" = "sourced-ok" ]
  [[ ! -f "$CALLS" ]]
}

@test "refuses to proceed when not on the main branch" {
  git -C "$DOTFILES" checkout -q -b other-branch
  _run_migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Not on main branch"* ]]
  [[ ! -f "$CALLS" ]] # never reached the DOT steps
}

@test "runs the full step sequence via DOT in order: clean, link, doctor" {
  _run_migrate
  [ "$status" -eq 0 ]
  [ -f "$CALLS" ]
  # Order matters: clean before link before doctor.
  run grep -n . "$CALLS"
  [[ "${lines[0]}" == *"dot clean"* ]]
  [[ "${lines[1]}" == *"dot link all --force -v"* ]]
  [[ "${lines[2]}" == *"dot doctor"* ]]
}

@test "reports Homebrew not installed and continues when brew is absent" {
  _run_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Homebrew not installed"* ]]
  # Migrate must still reach and run doctor afterwards (soft-fail semantics).
  grep -qx "dot doctor" "$CALLS"
}

@test "a failing doctor step does not fail migrate (doctor is best-effort)" {
  export FAKE_DOT_DOCTOR_EXIT=1
  _run_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Migration complete"* ]]
}
