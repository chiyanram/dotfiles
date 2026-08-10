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

The hooks above are repo-scoped (`.claude/`, registered in `.claude/settings.json`).
There is also one **user-level** hook that this repo ships, since losing it costs
more than a lint warning:

- `home/.claude/hooks/block-dangerous-git.sh` (PreToolUse, `Bash` matcher) —
  symlinked to `~/.claude/hooks/` by `dot link`. Refuses destructive git
  commands everywhere, and history-writing ones (`commit`, `push`) outside a
  trusted repo. Trust is never hardcoded (#180): the hook resolves its own
  symlink back to the checkout that owns it, so this repo trusts itself, and
  other repos are listed one per line in the untracked
  `~/.claude/hooks/trusted-git-repos.local`.

  Its registration ships in `home/.claude/settings.json.seed`, so a **fresh**
  machine is wired up by `dot link` while an existing one is not — `settings.json`
  is app-owned once present (ADR-0008). Add the `PreToolUse` entry by hand there,
  or `dot link --reseed`.

  Patterns are anchored to command position (start of line or after `;`/`&`/`|`),
  not matched as bare substrings. That is deliberate: the previous substring
  matcher blocked writing documentation that merely quoted a guarded command,
  and a guard you have to route around stops being a guard. `tests/claude_git_guard.bats`
  pins both halves — that invocations are caught and that prose is not.

  `(` is **not** in the separator set, so parenthesised prose ("forced pushes
  (`git push --force`)") passes; a genuine subshell is still caught by the `&&`
  or `;` inside it. One limit remains and is not fixable with a line-oriented
  matcher: a heredoc line that _begins_ with a guarded command is
  indistinguishable from a real newline-separated one, and is refused.

  It does not `set -e`, and does not source `common.sh` or resolve `DOTFILES`
  the way a `dot-*` script must. Both are deliberate and both are commented in
  the file: Claude Code reads exit 2 as "refuse" and any other non-zero as a
  non-blocking error, so a hook that aborts mid-check fails **open**; and the
  hook runs from `~/.claude` on any machine, including before this repo is
  cloned, so it has to stand alone. It is still in `dot-test`'s `bash_scripts()`
  (shellcheck + shfmt), which is the part of the ADR-0003 rigor list that does
  apply to it.

  **Migrating an existing machine.** If `~/.claude/hooks/block-dangerous-git.sh`
  already exists as a hand-installed real file, `dot link` classifies it `real`
  and refuses to touch it — correct, but it means the tracked version is not in
  use. Delete the file and re-run `dot link`, or `dot link --adopt`. Verify with
  `readlink ~/.claude/hooks/block-dangerous-git.sh`, which should point into this
  repo. And because `settings.json` is app-owned once present (ADR-0008), the
  seed's `PreToolUse` registration reaches a **fresh** machine only — on an
  existing one, add that entry by hand or `dot link --reseed`.

## Skills (`.claude/skills/<name>/SKILL.md`)

Only skills that are _about this repo_ live here. Generic, third-party skills are
user-level state: they install into `~/.claude/skills` + `~/.agents/skills` via the
`skills` CLI and are not vendored here (#168). `.agents/` and `skills-lock.json`
are gitignored so running that CLI with cwd set to this repo can't re-vendor them.

- `pr-close-issue` — runs `dot-test`, opens the PR with `Closes #N`, checks CI
  (not just local green — see issue #59), reminds to squash-merge.
- `brewfile-add` — adds a `brew/Brewfile.*` entry against the four documented
  rules (category, OS guard, no deprecated taps, trailing comment).
- `doctor-triage` — maps a `dot doctor` report's sections to their fixes.
- `setup-engineering-skills` — one-shot scaffolder that produced this repo's
  `docs/agents/*` (issue tracker, triage labels, domain docs). Kept because it
  isn't distributed by the `skills` CLI, so a reinstall wouldn't bring it back.

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
