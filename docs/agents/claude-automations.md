# Claude Code automations

Repo-specific hooks, skills, and subagents added under issue #65, on top of the
skills/plugins that ship independently of this repo. These exist to plug gaps
CLAUDE.md's rules alone don't structurally close — e.g. issue #59 (`dot-test`
doesn't cover pre-commit-only checks) let PR #64 land with four new lib files
missing their executable bit, since nothing local caught it before CI did.

## Hooks (`.claude/settings.json`, scripts in `.claude/hooks/`)

- `chmod-shebang.sh` (PostToolUse) — chmod +x any `bin/**` file with a shebang
  that isn't executable yet. Directly closes the PR #64 gap.
- `shfmt-on-save.sh` / `shellcheck-on-save.sh` (PostToolUse) — auto-format and
  lint-report touched bash files at edit time, in this repo's house style
  (`shfmt -i 2 -ci`), rather than waiting for a full `dot-test` run.
- `scoped-bats-on-save.sh` (PostToolUse) — best-effort run the bats file(s)
  matching the touched script's name for faster feedback than a full suite.
- `prettier-md-on-save.sh` (PostToolUse) — auto-format touched markdown with
  the same prettier version pinned in `.pre-commit-config.yaml`.
- `block-identity-config.sh` (PreToolUse) — blocks identity/auth config
  (`insteadOf`, `signingkey`, `email =`) from landing in the shared, symlinked
  `config/git/config`; that data belongs in `~/.gitconfig-local`.

All are non-blocking except the identity-config guard. None enforce working in
a worktree — that was discussed and deliberately left undone as a default.

## Skills (`.claude/skills/<name>/SKILL.md`)

- `pr-close-issue` — runs `dot-test`, opens the PR with `Closes #N`, checks CI
  (not just local green — see issue #59), reminds to squash-merge.
- `brewfile-add` — adds a `brew/Brewfile.*` entry against the four documented
  rules (category, OS guard, no deprecated taps, trailing comment).
- `doctor-triage` — maps a `dot doctor` report's sections to their fixes.

## Subagents (`.claude/agents/<name>.md`)

- `bash-pitfalls-reviewer` (read-only) — reviews diffs against CLAUDE.md's
  bash gotcha list (day-0/bash-3.2 safety, `return` vs `exit`, spinner usage,
  etc.) — the failure modes generic shellcheck/shfmt don't catch.
- `docs-drift-checker` (read-only) — flags a code change that should have
  moved a doc but didn't, per "every change updates its docs."
- `brewfile-reviewer` (read-only) — same four Brewfile rules as the
  `brewfile-add` skill, applied as a review pass instead of an authoring aid.
- `shellcheck-shfmt-fixer` — applies mechanical shellcheck/shfmt fixes across
  a set of changed files in this repo's house style.
