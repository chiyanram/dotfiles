# Tests for the git preflight helpers (_git_require_repo, _git_require_clean,
# _git_has_origin/_git_require_origin, _git_current_branch, _git_default_branch)
# shared by gcom/grbm/gpum in home/.zsh_functions, plus the three public
# functions themselves. Real temp git repos, not mocks — these functions are
# thin wrappers around real git plumbing (rev-parse, diff, branch, remote
# show), so a fake `git` would just re-encode the same assumptions being tested.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  ZSHFUNCS="$REPO/home/.zsh_functions"
  command -v zsh >/dev/null || skip "zsh not installed"
  SANDBOX="$(mktemp -d)"
  export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

# A bare "origin" whose HEAD is main, plus a clone with one commit and a
# checked-out feature branch — the shared fixture for tests that need a real
# remote (default-branch-via-remote, gcom/grbm/gpum integration).
make_origin_and_clone() {
  git init -q --bare --initial-branch=main "$SANDBOX/origin.git"
  git clone -q "$SANDBOX/origin.git" "$SANDBOX/work"
  (
    cd "$SANDBOX/work" || exit 1
    git checkout -q -b main
    echo one >file.txt
    git add file.txt
    git commit -q -m "init"
    git push -q origin main
    git remote set-head origin main
    git checkout -q -b feature
  )
}

run_zsh() { run zsh -c "source '$ZSHFUNCS'; $1"; }

# --- _git_require_repo -------------------------------------------------------

@test "_git_require_repo fails outside a git repository" {
  cd "$SANDBOX"
  run_zsh "_git_require_repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not a git repository."* ]]
}

@test "_git_require_repo succeeds inside a git repository" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  run_zsh "_git_require_repo"
  [ "$status" -eq 0 ]
}

# --- _git_require_clean ------------------------------------------------------

@test "_git_require_clean fails with uncommitted changes" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  echo one >file.txt
  git add file.txt
  git commit -q -m init
  echo two >>file.txt
  run_zsh "_git_require_clean"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "_git_require_clean succeeds with a clean working tree" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  echo one >file.txt
  git add file.txt
  git commit -q -m init
  run_zsh "_git_require_clean"
  [ "$status" -eq 0 ]
}

# --- _git_has_origin / _git_require_origin -----------------------------------

@test "_git_require_origin fails with no origin remote" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  run_zsh "_git_require_origin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No 'origin' remote found."* ]]
}

@test "_git_require_origin succeeds with an origin remote" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  git remote add origin "$SANDBOX/somewhere.git"
  run_zsh "_git_require_origin"
  [ "$status" -eq 0 ]
}

# --- _git_current_branch -----------------------------------------------------

@test "_git_current_branch prints the checked-out branch name" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  git checkout -q -b feature
  echo one >file.txt
  git add file.txt
  git commit -q -m init
  run_zsh "_git_current_branch"
  [ "$status" -eq 0 ]
  [ "$output" = "feature" ]
}

@test "_git_current_branch fails in detached HEAD" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  echo one >file.txt
  git add file.txt
  git commit -q -m init
  git checkout -q --detach HEAD
  run_zsh "_git_current_branch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not determine current branch."* ]]
}

# --- _git_default_branch ------------------------------------------------------

@test "_git_default_branch falls back to a local main ref with no origin" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  git checkout -q -b main
  echo one >file.txt
  git add file.txt
  git commit -q -m init
  run_zsh "_git_default_branch"
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

@test "_git_default_branch falls back to a local master ref when main is absent" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  git checkout -q -b master
  echo one >file.txt
  git add file.txt
  git commit -q -m init
  run_zsh "_git_default_branch"
  [ "$status" -eq 0 ]
  [ "$output" = "master" ]
}

@test "_git_default_branch errors (to stderr) when nothing can be determined" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  run_zsh "_git_default_branch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not determine default branch."* ]]
}

@test "_git_default_branch prefers the remote HEAD branch when origin exists" {
  make_origin_and_clone
  cd "$SANDBOX/work"
  run_zsh "_git_default_branch"
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

@test "_git_default_branch does not leak its error text into a captured value" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  run_zsh 'x=$(_git_default_branch); echo "captured=[$x]"'
  [[ "$output" == *"captured=[]"* ]]
}

# --- gcom ---------------------------------------------------------------------

@test "gcom switches to the remote-detected default branch" {
  make_origin_and_clone
  cd "$SANDBOX/work"
  run_zsh "gcom"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Switching to main"* ]]
  run git -C "$SANDBOX/work" branch --show-current
  [ "$output" = "main" ]
}

@test "gcom refuses with uncommitted changes" {
  make_origin_and_clone
  cd "$SANDBOX/work"
  echo dirty >file.txt
  run_zsh "gcom"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "gcom -h prints usage and exits 0" {
  cd "$SANDBOX"
  run_zsh "gcom -h"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: gcom"* ]]
}

# --- grbm -----------------------------------------------------------------

@test "grbm rebases the feature branch onto the default branch" {
  make_origin_and_clone
  cd "$SANDBOX/work"
  run_zsh "grbm"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rebasing feature against main"* ]]
}

@test "grbm reports nothing to do when already on the default branch" {
  make_origin_and_clone
  cd "$SANDBOX/work"
  git checkout -q main
  run_zsh "grbm"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already on main. Nothing to rebase."* ]]
}

@test "grbm fails with no origin remote" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  echo one >file.txt
  git add file.txt
  git commit -q -m init
  run_zsh "grbm"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No 'origin' remote found."* ]]
}

# --- gpum -----------------------------------------------------------------

@test "gpum pushes the current branch to origin with upstream tracking" {
  make_origin_and_clone
  cd "$SANDBOX/work"
  run_zsh "gpum"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pushing feature to origin"* ]]
  run git -C "$SANDBOX/origin.git" show-ref --verify --quiet refs/heads/feature
  [ "$status" -eq 0 ]
}

@test "gpum fails with no origin remote" {
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo"
  echo one >file.txt
  git add file.txt
  git commit -q -m init
  run_zsh "gpum"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No 'origin' remote found."* ]]
}
