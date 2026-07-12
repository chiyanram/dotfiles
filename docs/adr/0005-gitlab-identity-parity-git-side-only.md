# 5. GitLab identity parity is git-side only; key registration is a first-class `dot git` verb

Date: 2026-07-08

## Status

Accepted

## Context

The identity-slot system (ADR 0001) was built host-agnostic: `add-identity
--host <host>` already produces a working slot for any host, and
`git_slot_status` (`bin/lib/git-slots.sh`) already treats `gitlab.com` as a
first-class forge. What was _not_ host-agnostic were the CLI conveniences wired
around `gh`:

- `setup.sh` uploads the day-0 key via `gh ssh-key add` (GitHub only), and
  `add-identity` never uploads a slot key at all — it prints the pubkey and
  makes you paste it into the host's web UI by hand (true for GitHub too).
- `dot git use` runs `gh auth switch --user` to align the active CLI account to
  the slot (GitHub only).
- `dot doctor` runs `ssh -T git@github.com` and warns on `gh` account drift.

Extending this to GitLab surfaced one hard asymmetry between the two CLIs:

- **`gh` is multi-account per host** with an _active_ selection —
  `gh auth switch --user` is the mechanism `dot git use` depends on.
- **`glab` stores one token per host** (its `config.yml` keys `hosts:` by
  hostname) and has **no `auth switch --user`** verb (only `login/logout/status`
  as of v1.107.0). Two `gitlab.com` accounts cannot coexist.

So the GitHub model — "binding a slot also re-points the CLI at the right
account" — has no clean GitLab analog.

## Decision

**GitLab identity slots bind git-side only.** `dot git use` on a GitLab slot
rewrites `origin` to the slot alias (so key, email, and SSH signing follow) and
stops there — it does **not** attempt any `glab` account switch. The SSH alias
is what makes push and commit-signing correct; CLI-account sync was never the
point of a slot. This mirrors what `use` already does when `gh` is absent: log
and move on.

Consequently, the per-slot `gitlab.user` field and a `glab`-drift check in
`dot doctor` are **not built** — they exist only to serve account switching,
which cannot happen. They are deferred until a real second GitLab account
exists (and glab's account model can be re-evaluated then).

**Key registration becomes a first-class, host-aware `dot git register-key`
verb** rather than inline CLI calls:

- Picks the CLI by host: `github.*` → `gh ssh-key add` (two calls —
  `--type authentication` then `--type signing`, since gh treats them as
  separate keys); `gitlab.*` → `glab ssh-key add --usage-type auth_and_signing`
  (one call — glab's default already covers both).
- Is **account-scoped, not repo-scoped** — a key belongs to your account, so
  the command needs `--host` + `--key`, never a repo.
- Ensures the host key is trusted (`ensure_known_host <host>`) as a
  precondition, so a freshly-registered key doesn't fail the first `ssh`.
- Degrades to print-and-paste when the CLI is missing or unauthenticated.
- Is called automatically by `add-identity` (fixing GitHub's manual-paste too)
  and reused by `setup.sh`.

`dot doctor`'s GitLab SSH check runs only when `glab` is authenticated **or** a
`gitlab.com` slot exists — silent on pure-GitHub machines.

## Consequences

- Every `gitlab.com` repo — personal account or not — needs a slot once the
  Identity Guard is active: `git_slot_status`'s `is_forge` check treats
  `gitlab.com` unconditionally, the same as `github.com`/`bitbucket.org`, with
  no personal-account carve-out. A carve-out isn't just unbuilt — it can't be
  built safely: the Guard would need to tell "personal" apart from "not yet
  bound" _before_ a slot exists, which is exactly the ambiguity the Guard
  exists to close. Approximating it any other way would weaken the
  misattribution protection ADR-0001 was built for. `dot git register-key` is
  still the one command that makes SSH work once the slot exists.
- GitHub gains auto key-registration on `add-identity`, not just GitLab — the
  change is a net DRY improvement, not a GitLab special-case.
- If a client ever issues a distinct GitLab account, CLI-account juggling stays
  **manual** (`glab auth login`). Revisit this ADR then; do not assume the
  git-side-only decision was an oversight.
