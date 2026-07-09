setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  # Pin DOTFILES so dot-update sources THIS tree's libs, not an inherited one.
  export DOTFILES="$REPO"
  UPDATE="$REPO/bin/dot-update"
}

# Source dot-update (guarded so main does not run) and classify a failed
# `git pull` log: kind <log-content> -> untracked-collision | other.
kind() {
  local log
  log="$(mktemp)"
  printf '%s' "$1" >"$log"
  run bash -c "source '$UPDATE'; _dotfiles_pull_failed_kind '$log'"
  rm -f "$log"
}

@test "pull failure: untracked-file collision is detected" {
  kind "error: The following untracked working tree files would be overwritten by merge:
	.claude/skills/triage/SKILL.md
	skills-lock.json
Please move or remove them before you merge.
Aborting"
  [ "$output" = "untracked-collision" ]
}

@test "pull failure: a generic network error is 'other'" {
  kind "fatal: unable to access 'https://github.com/x/y': Could not resolve host"
  [ "$output" = "other" ]
}
