---
name: pr-close-issue
description: Close out a branch in this repo the documented way — verify ./bin/dot-test is green, open a PR with "Closes #N", and remind to squash-merge. Use when the user says the work on a branch/worktree is done and wants to open or land the PR.
disable-model-invocation: true
---

# Close an Issue Through a PR

CLAUDE.md: "Open a PR with `Closes #N` in the body and squash-merge to `main`; the merge is what closes the issue." This skill runs that closing ritual in order — don't skip the test-gate step even if earlier commits on the branch already passed it.

## Steps

1. **Confirm you're in the worktree for this branch**, not the shared checkout (`git rev-parse --show-toplevel` should point under `.claude/worktrees/`).

2. **Run the test gate and show its output**: `./bin/dot-test` (the worktree's own copy — it always tests its own tree regardless of an inherited `DOTFILES`). Don't claim "done" or draft the PR until this is green — "fixed/passing/works" are verified claims per CLAUDE.md, not assumptions.

3. **Push the branch** if it isn't already up to date with the remote.

4. **Open the PR** with `gh pr create`, body including `Closes #N` (use the actual issue number — a `Closes #N` commit/PR only takes effect once it lands on `main` via merge). Follow this repo's PR body conventions: a `## Summary` and `## Test plan` section (see recent merged PRs for the exact shape, e.g. `gh pr view <recent-pr-number>`).

5. **Check CI**, not just local `dot-test` — `gh pr checks <number>`. This repo runs a separate `pre-commit hooks` CI job that `dot-test` does **not** cover (tracked as issue #59) — e.g. `check-shebang-scripts-are-executable` only runs there. Don't consider the PR ready on local green alone; wait for or check the CI status.

6. **Squash-merge**, don't just merge — CLAUDE.md is explicit about this. Confirm with the user before merging unless they've already asked for it in this conversation.

7. **After merge**: exit the worktree (`ExitWorktree` with `action: "remove"` once the branch is merged and there's nothing left to keep), and confirm the shared checkout is back on `main` and clean.
