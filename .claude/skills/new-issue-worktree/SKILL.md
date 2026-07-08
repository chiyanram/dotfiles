---
name: new-issue-worktree
description: Scaffold this repo's issue -> branch -> worktree ritual for non-trivial work (open a GitHub issue, create a correctly-named branch, enter a worktree). Use when the user wants to start work on a new feature/fix/refactor in this dotfiles repo and there's no issue/branch yet.
disable-model-invocation: true
---

# New Issue + Worktree

CLAUDE.md mandates a specific ritual for every non-trivial change in this repo: open an issue, branch `<type>/<issue-number>-<brief-description>` off it, and do the work in a worktree under `.claude/worktrees/` — never in the shared checkout. This skill scaffolds all three steps in order and gets the naming right the first time.

## Steps

1. **Confirm this needs the ritual.** Skip it only for a pure prose/comment change to an existing doc (README.md, CLAUDE.md, CONTEXT.md, an ADR) with no script/test/config touched — CLAUDE.md's one documented exception. Everything else gets an issue.

2. **Open the issue.**

   ```
   gh issue create --title "<concise title>" --body "<what/why, and a checklist if the work has multiple pieces>"
   ```

   Note the issue number from the output URL.

3. **Pick the type prefix** from Conventional Commits: `feat`, `fix`, `chore`, `refactor`, `docs`. Build the branch name: `<type>/<issue-number>-<brief-description>` (lowercase, hyphenated, short).

4. **Enter a worktree, then rename the branch.** `EnterWorktree` creates a worktree with an auto-generated branch name (e.g. `worktree-<name>`) — it does **not** know this repo's naming convention. Always rename immediately after:

   ```
   git branch -m <type>/<issue-number>-<brief-description>
   ```

   Verify with `git branch --show-current` before doing any work — a stray `worktree-*` branch name is easy to miss and will look wrong in the eventual PR.

5. **Work small, commit small.** One logical change per commit, push as you go, run `./bin/dot-test` (the worktree's own copy — it always tests its own tree) before opening the PR.

6. **Close through a PR.** See the `pr-close-issue` skill for the closing half of this ritual.
