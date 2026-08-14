load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

# The Claude Code git guard (#180). It is a PreToolUse hook: Claude Code pipes
# it JSON on stdin and reads a decision back.
#
# The guard ASKS rather than refuses. It prints a `permissionDecision: "ask"`
# payload and exits 0, so Claude Code shows its normal permission prompt and the
# human decides. It used to exit 2, which blocks outright and never reaches
# anyone — and an unoverridable guard invites the workaround: reach for a command
# shape the pattern misses (`git -C …` was exactly that) and nobody is prompted
# at all. A checkpoint that can be answered is stronger than a wall that can be
# walked around.
#
# These tests run the real, tracked hook out of the repo rather than a fixture —
# the point of #180 is that the repo owns this file, so the repo's tests are
# what keep it honest.

REPO_HOOK() { echo "$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)/home/.claude/hooks/block-dangerous-git.sh"; }

# Feed the hook one tool call. $1 command, $2 cwd.
run_guard() {
  local cmd="$1" cwd="$2"
  run bash -c "printf '{\"cwd\":\"%s\",\"tool_input\":{\"command\":\"%s\"}}' '$cwd' '$cmd' | '$(REPO_HOOK)'"
}

# allow and ask both exit 0 now, so the exit code alone no longer says which
# happened — an over-broad pattern that started asking about `git status` would
# pass a bare status check. Assert on the decision itself.
assert_asked() {
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

assert_allowed() {
  [ "$status" -eq 0 ]
  [[ "$output" != *'"permissionDecision"'* ]]
}

########################################
# Tracked and linked
########################################

@test "the repo ships the git guard as an executable hook under home/.claude" {
  hook="$(REPO_HOOK)"
  [ -f "$hook" ]
  [ -x "$hook" ]
  run sed -n '1p' "$hook"
  [[ "$output" == "#!"* ]]
}

@test "dot link maps a nested home/.claude/hooks file to ~/.claude/hooks" {
  mkdir -p "$DOTFILES/home/.claude/hooks"
  printf '#!/bin/bash\nexit 0\n' >"$DOTFILES/home/.claude/hooks/demo-hook.sh"
  chmod +x "$DOTFILES/home/.claude/hooks/demo-hook.sh"
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/hooks/demo-hook.sh" ]
  [ -x "$HOME/.claude/hooks/demo-hook.sh" ]
}

@test "the seed registers the hook so a fresh machine gets it wired up" {
  seed="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)/home/.claude/settings.json.seed"
  run grep -c 'block-dangerous-git.sh' "$seed"
  [ "$status" -eq 0 ]
  # and it must be valid JSON, or Claude Code ignores the whole file. jq, not
  # python3: jq is already this hook's hard dependency and a Brewfile.core entry,
  # so it is the one interpreter the suite may assume.
  run jq -e . "$seed"
  [ "$status" -eq 0 ]
}

# Every other test runs the repo file directly, but production runs it through
# the symlink `dot link` creates — which is the only path where the self-locating
# trust resolution has to survive a readlink. Cover the path that actually ships.
@test "trust resolution survives being invoked through the dot link symlink" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  mkdir -p "$HOME/.claude/hooks"
  ln -s "$repo/home/.claude/hooks/block-dangerous-git.sh" "$HOME/.claude/hooks/block-dangerous-git.sh"
  run bash -c "printf '{\"cwd\":\"%s\",\"tool_input\":{\"command\":\"git commit -m x\"}}' '$repo' | '$HOME/.claude/hooks/block-dangerous-git.sh'"
  assert_allowed
  run bash -c "printf '{\"cwd\":\"%s\",\"tool_input\":{\"command\":\"git commit -m x\"}}' '$SANDBOX' | '$HOME/.claude/hooks/block-dangerous-git.sh'"
  assert_asked
}

# An existing machine already has a hand-installed real file at the target, so
# `dot link` classifies it `real` and refuses rather than clobbering it. That is
# correct behaviour, and it is the migration step the docs have to mention.
@test "an existing real file at the hook target is reported as a conflict, not clobbered" {
  mkdir -p "$DOTFILES/home/.claude/hooks" "$HOME/.claude/hooks"
  printf '#!/bin/bash\nexit 0\n' >"$DOTFILES/home/.claude/hooks/demo-hook.sh"
  printf 'HAND-INSTALLED\n' >"$HOME/.claude/hooks/demo-hook.sh"
  run "$DOT" link all
  [ ! -L "$HOME/.claude/hooks/demo-hook.sh" ]
  [ "$(cat "$HOME/.claude/hooks/demo-hook.sh")" = "HAND-INSTALLED" ]
}

########################################
# Always asked about, every repo
########################################

@test "destructive commands prompt inside the dotfiles repo too" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  for cmd in "git reset --hard" "git clean -fd" "git branch -D topic" "git push --force" "git checkout ." "git restore ."; do
    run_guard "$cmd" "$repo"
    assert_asked || {
      echo "expected a prompt for: $cmd"
      return 1
    }
  done
}

########################################
# Trusted-repo scoping — no hardcoded personal path
########################################

@test "commit and push are allowed inside the dotfiles repo the hook belongs to" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  run_guard "git commit -m x" "$repo"
  assert_allowed
  run_guard "git push -u origin topic" "$repo"
  assert_allowed
}

@test "commit and push are allowed in a worktree under the dotfiles repo" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  run_guard "git commit -m x" "$repo/.claude/worktrees/some-branch"
  assert_allowed
}

@test "commit and push prompt outside any trusted repo" {
  run_guard "git commit -m x" "$SANDBOX"
  assert_asked
  run_guard "git push" "$SANDBOX"
  assert_asked
}

@test "the hook contains no hardcoded home directory path" {
  run grep -n '/Users/' "$(REPO_HOOK)"
  [ "$status" -ne 0 ]
}

@test "extra trusted repos come from the untracked local sink" {
  mkdir -p "$HOME/.claude/hooks"
  printf '%s\n' "$SANDBOX/work" >"$HOME/.claude/hooks/trusted-git-repos.local"
  run_guard "git commit -m x" "$SANDBOX/work"
  assert_allowed
  run_guard "git commit -m x" "$SANDBOX/other"
  assert_asked
}

@test "blank lines and comments in the local sink are ignored" {
  mkdir -p "$HOME/.claude/hooks"
  printf '# a comment\n\n%s\n' "$SANDBOX/work" >"$HOME/.claude/hooks/trusted-git-repos.local"
  run_guard "git commit -m x" "$SANDBOX/work"
  assert_allowed
  # an empty line must not become a prefix that matches everything
  run_guard "git commit -m x" "$SANDBOX/elsewhere"
  assert_asked
}

########################################
# The matcher fires on invocations, not prose
########################################

@test "prose mentioning a dangerous pattern does not prompt" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  run_guard "gh issue create --body The fix avoids a reset --hard here" "$repo"
  assert_allowed
  run_guard "echo documenting git clean -fd for the runbook" "$repo"
  assert_allowed
}

# Parenthesised prose is the common shape in an issue body or commit message.
# `(` is deliberately not a command separator for this reason — a genuinely
# chained subshell is still caught by the && or ; inside it (below).
@test "a guarded command quoted inside parentheses in prose does not prompt" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  run_guard "gh issue create --body forced pushes (git push --force) are refused" "$repo"
  assert_allowed
  run_guard "gh pr comment --body see the guard (git reset --hard is blocked)" "$repo"
  assert_allowed
}

@test "a subshell that chains into a dangerous command is still caught" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  run_guard "(cd /tmp && git reset --hard)" "$repo"
  assert_asked
}

@test "ordinary read-only git never prompts" {
  run_guard "git status --short" "$SANDBOX"
  assert_allowed
  run_guard "git log --oneline -5" "$SANDBOX"
  assert_allowed
}

# Two fail-open paths, both closed here. Without jq the command cannot be parsed
# out of the payload, so the hook scans the raw JSON instead — coarser, but
# closed. And the ask-payload itself needs jq to build: a jq that is PRESENT and
# BROKEN (what this test installs) would otherwise let the hook exit 0 having
# printed nothing, allowing the command with no prompt. Both degrade to exit 2.
@test "the guard does not fail open when jq is unavailable" {
  stub="$SANDBOX/nojq"
  mkdir -p "$stub"
  printf '#!/bin/sh\nexit 127\n' >"$stub/jq"
  chmod +x "$stub/jq"
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  # Note the inner PATH must stay double-quoted: single quotes would make it the
  # literal string "$PATH", leaving the hook unable to find grep either — which
  # looks like the guard passing when it is simply broken.
  run bash -c "printf '{\"cwd\":\"%s\",\"tool_input\":{\"command\":\"git reset --hard\"}}' '$repo' | PATH=\"$stub:\$PATH\" '$(REPO_HOOK)'"
  [ "$status" -eq 2 ]
}

@test "a dangerous command chained after another is still caught" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  run_guard "cd /tmp && git reset --hard" "$repo"
  assert_asked
  run_guard "true; git clean -fd" "$repo"
  assert_asked
}

########################################
# Global options between `git` and the subcommand
########################################

# Every pattern used to anchor `git` directly against its subcommand, so any
# global option in between made the whole guard miss: `git -C /path push
# --force` matched nothing and ran. Found in production rather than by review —
# an agent reached for `-C` to avoid a `cd` (a separate house rule) and the
# force-push it had already been refused twice went straight through.
#
# The hole was never push-specific. Every rule shared the anchor, so every rule
# had it.

@test "a global option before the subcommand does not evade the dangerous rules" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  for cmd in \
    "git -C /tmp/x push --force origin main" \
    "git -C /tmp/x push --force-with-lease origin main" \
    "git -C /tmp/x reset --hard HEAD~1" \
    "git -C /tmp/x clean -fd" \
    "git -C /tmp/x branch -D topic" \
    "git -C /tmp/x checkout ." \
    "git -C /tmp/x restore ."; do
    run_guard "$cmd" "$repo"
    assert_asked || {
      echo "expected a prompt for: $cmd"
      return 1
    }
  done
}

@test "every global-option form is covered, not just -C" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  for cmd in \
    "git -C/tmp/x push --force" \
    "git --git-dir=/tmp/x/.git reset --hard" \
    "git --work-tree=/tmp/x clean -fd" \
    "git -c user.name=x push --force" \
    "git --no-pager push --force" \
    "git -C /tmp/x --no-pager push --force"; do
    run_guard "$cmd" "$repo"
    assert_asked || {
      echo "expected a prompt for: $cmd"
      return 1
    }
  done
}

# The obvious fix — accept any `-…` token followed by an optional value —
# reintroduces the same bug one layer down: `--no-pager` takes no value, so the
# optional-value branch swallows `push`, the pattern stops matching, and the
# guard fails open again. The option forms are enumerated for exactly that
# reason, and this test is what stops anyone "simplifying" it back.
@test "a valueless global option does not swallow the subcommand" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  run_guard "git --no-pager push --force" "$repo"
  assert_asked
  run_guard "git --paginate reset --hard" "$repo"
  assert_asked
}

@test "global options do not make read-only git look dangerous" {
  run_guard "git -C /tmp/x status --short" "$SANDBOX"
  assert_allowed
  run_guard "git -C /tmp/x log --oneline -5" "$SANDBOX"
  assert_allowed
  run_guard "git --no-pager diff --stat" "$SANDBOX"
  assert_allowed
  # -d deletes only an already-merged branch; -D is the destructive form
  run_guard "git -C /tmp/x branch -d merged-topic" "$SANDBOX"
  assert_allowed
}

@test "trusted-repo scoping still applies through a global option" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  run_guard "git -C /tmp/x commit -m x" "$repo"
  assert_allowed
  run_guard "git -C /tmp/x commit -m x" "$SANDBOX"
  assert_asked
  run_guard "git -C /tmp/x push origin main" "$SANDBOX"
  assert_asked
}
