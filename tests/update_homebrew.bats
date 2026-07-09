setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  # Pin DOTFILES so dot-update sources THIS tree's libs, not an inherited one.
  export DOTFILES="$REPO"
  UPDATE="$REPO/bin/dot-update"
}

# Source dot-update (guarded so main does not run) and classify a captured
# `brew update && brew upgrade` run: outcome <exit_status> <log-content>.
outcome() {
  local log
  log="$(mktemp)"
  printf '%s' "$2" >"$log"
  run bash -c "source '$UPDATE'; _brew_update_outcome '$1' '$log'"
  rm -f "$log"
}

@test "brew outcome: 'Already up-to-date' is ok, not changed" {
  outcome 0 "==> Updating Homebrew...
Already up-to-date."
  [ "$output" = "ok" ]
}

@test "brew outcome: a real upgrade is changed" {
  outcome 0 "==> Upgraded 11 outdated packages
mise           2026.7.0       -> 2026.7.2
go             1.26.4         -> 1.26.5"
  [ "$output" = "changed" ]
}

@test "brew outcome: benign 'Failed'/'Error' text with a zero exit is not a failure" {
  outcome 0 "==> Updating Homebrew...
Warning: Failed to link some optional files (non-fatal)
Already up-to-date."
  [ "$output" != "failed" ]
}

@test "brew outcome: a non-zero exit is a failure" {
  outcome 1 "Error: some cask failed to install"
  [ "$output" = "failed" ]
}
