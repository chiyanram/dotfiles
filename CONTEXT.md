# Dotfiles

Personal dotfiles for a macOS work laptop. This glossary pins down terms that are
specific to this repo's conventions — not general shell/git concepts.

## Language

### Link management

**Managed Target**:
A source/target/label triple `dot link`/`dot unlink` know about — a config
package (`config/<pkg>` → `~/.config/<pkg>`) or a home file (`home/<rel>` →
`~/<rel>`). Enumerated by `managed_targets`, the single source of truth for
"what does `dot link` manage."
_Avoid_: Symlink, config file (a Managed Target is the source/target _pairing_,
not either path alone).

**Link State**:
The four-way classification `classify_link` assigns to a Managed Target —
`missing`, `ok`, `wrong`, or `real` — shared by every command that inspects or
acts on links (`link_plan`, `link_status`, `link_apply`, `unlink_apply`) so they
can never disagree about a target's state. `wrong` means "points somewhere other
than the expected source" — this includes a truly foreign symlink _and_ a stale
pointer left by a renamed package; both are treated identically as "not ours to
touch."
_Avoid_: Broken, dangling (those describe a different condition — a symlink whose
target no longer resolves at all, handled separately by `dot clean`).

**Apply Function**:
`link_apply` or `unlink_apply` — performs the real filesystem mutation for one
Managed Target, deciding via its Link State, and recording an undo row to the
active Manifest. The two directions are separate functions sharing only
`classify_link`, not one function with a mode flag, since the two directions
need materially different parameters (`link_apply` needs `force`/`backup`/
`adopt`; `unlink_apply` needs none of them).
_Avoid_: Handler, action (too generic — this term ties specifically to the
classify-then-mutate-then-record shape).

**Manifest**:
The per-run undo log (`$STATE_DIR/manifest-<timestamp>-<pid>.tsv`) an Apply
Function appends a row to after every mutation; `dot restore` replays it in
reverse. A row is `<action>\t<target>\t<prev>`, where `prev` is whatever
`<target>` should become on undo (empty means "remove it").
_Avoid_: Log, history (Manifest is specifically the undo mechanism, consumed
exactly once by `dot restore`, not a durable audit trail).

### Git identity

**Identity Slot**:
A named git identity bundled as a set that always travels together — an SSH
key (used for both auth _and_ commit signing via `gpg.format=ssh`), an SSH host
alias that selects that key, and a gitconfig fragment carrying the commit email
and signing config. A slot is keyed by **account**, not by org — one slot spans
every org that account can reach (e.g. the `ee` slot covers your employer's org
_and_ any client org that simply adds your work account). A client becomes its
**own** slot
only when it issues you a distinct account/email.
_Avoid_: Account, profile, persona (reserve "account" for the remote GitHub/GitLab account a slot pushes to).

**Slot Alias**:
The `<host>-<name>` SSH `Host` entry that routes a repo to a slot's key — e.g.
`github.com-ee` has `HostName github.com` but `IdentityFile id_ed25519_ee`. A
repo "is on" a slot when its remote URL uses that slot's alias.
_Avoid_: Host, remote name.

**Bind**:
The mechanism that makes a repo's commit email follow from its remote URL, via
`includeIf "hasconfig:remote.*.url:git@<host>-<name>:*/**"` (the `*/**` path glob is
required — git's hasconfig `**` only crosses `/` when slash-delimited, so a bare `:**`
never matches an scp URL's `owner/repo` path). Because the email is derived from the
same alias that selects the key, email can never drift from key — you never set
the email by hand.
_Avoid_: Configure identity, set email.

**Fallback Identity**:
The unconditional identity in `~/.gitconfig-local`, used only when no slot's
`hasconfig` rule matches (e.g. a local repo with no remote yet). It is
deliberately the **personal** identity, so a forgotten repo commits as you — never
as the wrong client.
_Avoid_: Default account (it is a safety net, not a preferred identity).

**Identity Guard**:
The `pre-commit` hook (installed globally via `core.hooksPath`) that blocks a
commit when the repo's remote is on a known host but matches no slot, and prints
the exact `dot git use <slot>` command to fix it. Auditable in bulk via
`dot doctor`.
_Avoid_: Validation, linter.

**Identity Audit**:
The report-only sweep in `dot doctor` that walks the conventional roots
(`~/work ~/workspace ~/dev ~/dotfiles ~/personal ~/clients`, plus any
`git_audit_roots` override that augments them) and lists mis-set repos and
**gh drift** (a slot-bound GitHub repo whose active `gh` account differs from the
slot's). It never writes and never gates the exit code — the Guard is the
enforcer; the audit is the proactive convenience sweep. The mis-set decision is
shared with the Guard via `bin/lib/git-slots.sh`, so the two can never disagree.
_Avoid_: calling it enforcement (it only reports).

**Migration**:
The interactive one-pass onboarding (`dot git migrate`) that walks the same repos
as the Identity Audit (shared discovery in `bin/lib/git-slots.sh`) and, per mis-set
repo, offers a slot and rebinds `origin` on confirmation (reusing `dot git use`'s
`bind_repo_to_slot`). It does the **durable git-side rebind only** — unlike
`dot git use` it never runs `gh auth switch`, because the active `gh` account is a
single global and thrashing it across many repos is wrong; gh aligns later when you
`use` (or work in) a specific repo. Re-runnable and non-destructive: the only change
ever made is a remote-URL rewrite, and an already-bound repo is left untouched.
_Avoid_: switching the gh account during migrate; touching remote-less repos.

**Removal**:
The symmetric teardown (`dot git remove-identity <slot>`) of everything
`add-identity` created for a slot: the SSH alias, the gitconfig fragment, its
`hasconfig` include, and its `allowed_signers` entry. Deletes the key pair only
if it was **managed** (generated by `add-identity`, at `~/.ssh/id_ed25519_<name>`);
an **adopted** key (brought in via `--key`) is left on disk with a warning, since
it may be shared with other uses. Also warns if any repo under the audit roots
still points at the alias, and reminds you to revoke the key on the host account —
first-class because a stale client key left registered is a compliance hazard.
_Avoid_: deleting an adopted key; treating the revoke reminder as automatic (it's
a manual step on the host, e.g. GitHub settings).
