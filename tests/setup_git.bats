setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX"

  # Fake DOT: records every invocation (name + args) to $CALLS in order.
  CALLS="$SANDBOX/calls"
  : >"$CALLS"
  DOT="$SANDBOX/fake-dot"
  cat >"$DOT" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$CALLS"
exit "\${FAKE_DOT_EXIT:-0}"
EOF
  chmod +x "$DOT"
  export DOT CALLS
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

_run_step_git() {
  # setup.sh's own top-level `NON_INTERACTIVE=0` runs on `source`, clobbering
  # an inherited env var — so set it as a plain assignment AFTER sourcing.
  run env HOME="$HOME" DOT="$DOT" CALLS="$CALLS" DOTFILES="$REPO" TERM=dumb bash -c '
      set -Eeuo pipefail
      source "'"$REPO"'/setup.sh"
      NON_INTERACTIVE='"${NON_INTERACTIVE:-0}"'
      rc=0; step_git || rc=$?
      echo "step_rc=$rc"
    '
}

@test "fresh + interactive: runs setup then install-guard" {
  NON_INTERACTIVE=0 _run_step_git
  [[ "$output" == *"step_rc=0"* ]]
  [ "$(cat "$CALLS")" = "$(printf 'git setup\ngit install-guard')" ]
}

@test "fresh + non-interactive: skips setup's prompt but still installs the guard" {
  NON_INTERACTIVE=1 _run_step_git
  [[ "$output" == *"step_rc=0"* ]]
  [[ "$output" == *"Skipping github.user prompt"* ]]
  [ "$(cat "$CALLS")" = "git install-guard" ]
}

@test "already configured: skips setup's prompt but still installs the guard" {
  : >"$HOME/.gitconfig-local"
  NON_INTERACTIVE=0 _run_step_git
  [[ "$output" == *"step_rc=0"* ]]
  [[ "$output" == *"already configured"* ]]
  [ "$(cat "$CALLS")" = "git install-guard" ]
}

@test "install-guard failure fails the step" {
  : >"$HOME/.gitconfig-local" # skip straight to install-guard
  FAKE_DOT_EXIT=1 _run_step_git
  [[ "$output" == *"step_rc=1"* ]]
}
