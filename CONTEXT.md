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

**Seed Target**:
A Managed Target applied by **copy-once** instead of symlink, for a file the
owning tool rewrites at runtime (e.g. Claude Code's `~/.claude/settings.json` —
model, `effortLevel`, theme, plugins). Declared by a `.seed` source suffix
(`home/.claude/settings.json.seed` → `~/.claude/settings.json`, suffix stripped).
`dot link` copies it only when the target is **absent** and never overwrites a
present one — the tool owns the live file thereafter, so a symlink (shared inode)
would let the tool's writes churn the repo. `dot link --reseed` is the deliberate
opt-in to overwrite (backing up first). Mirrors chezmoi's `create_`. See ADR-0008.
_Avoid_: Template (a seed is copied verbatim, not rendered per-machine — a
different mechanism); Config Leak (the leak is the _problem_ a Seed Target avoids —
an app-written file inside a symlinked dir; the Seed Target is the _resolution_).

**Link State**:
The classification `classify_link` assigns to a Managed Target — shared by every
command that inspects or acts on links (`link_plan`, `link_status`, `link_apply`,
`unlink_apply`) so they can never disagree about a target's state. For a symlink
target it is four-way — `missing`, `ok`, `wrong`, or `real`. `wrong` means "points
somewhere other than the expected source" — this includes a truly foreign symlink
_and_ a stale pointer left by a renamed package; both are treated identically as
"not ours to touch". `real` means a non-symlink file sits where the link should
go — a conflict `dot link` skips. For a Seed Target the same on-disk facts read
oppositely: a present real file is `seeded` (success — leave it, the tool owns
it), and only `missing` triggers action. (The `seeded` state is introduced by
ADR-0008; implementation tracked in #115.)
_Avoid_: Broken, dangling (those describe a different condition — a symlink whose
target no longer resolves at all, handled separately by `dot clean`).
The health axis of a Link State (is it a problem, y/n) is centralized in
`link_state_is_issue` (bin/lib/links.sh) — `link_status` and `dot-doctor`'s
`check_config_links`/`check_home_links` all defer to it for counting, so they
can't drift on what counts as "fine" (#145). `link_status` additionally uses
`link_state_color` for its GREEN/YELLOW/RED choice; `dot-doctor` deliberately
does **not** — its RED/YELLOW split is by fix-urgency (a wrong symlink is an
active misconfiguration, RED; a real file is just unmigrated, YELLOW), a
different axis than `link_status`'s health-based color, so its case
statement's colors stay literal rather than forced through the same helper.

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

**Config Leak**:
A file that lands inside a tracked, symlinked `config/*`/`home/*` directory as an
unintended byproduct of the tool it's symlinked for writing runtime/generated state
to its own directory — since the symlink means `$HOME/.config/<pkg>/...` and
`config/<pkg>/...` are the same location on disk. Detected via `git status`'s
untracked-file view, since the leak physically exists in the repo's own working
tree — no custom scanning needed.
_Avoid_: Drift (reserved for declared-vs-actual mismatches in the Brewfile/SDKMAN/
symlink domains — a leak is a different failure mode: an unexpected file existing,
not a state disagreeing with a declaration).

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

**No Fallback (`useConfigOnly`)**:
`user.useConfigOnly = true` in the shared `config/git/config` (#157): a commit
in a repo that matches no slot's `hasconfig` rule — including a scratch repo
with no remote at all — fails outright, full stop. There is no default identity
to fall back to, not even a "safe" one. This superseded the original **Fallback
Identity** design (a `[user]` block in `~/.gitconfig-local`, deliberately the
personal identity), rejected because any fallback value is itself state that
can silently drift out of sync with intent — as it already had once (the prior
`~/.gitconfig-local` EE-email drift bug). Unlike the Identity Guard, which is a
bypassable `pre-commit` hook not copied on clone, `useConfigOnly` operates
inside git's own commit machinery.
_Avoid_: Fallback identity, default identity (both describe the eliminated
pre-#157 design).

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
**gh drift** (a slot-bound GitHub repo whose `gh` account differs from the
slot's) — judged against the slot's Dedicated gh Config when one exists,
falling back to the single global active account otherwise. It never writes
and never gates the exit code — the Guard is the enforcer; the audit is the
proactive convenience sweep. The mis-set decision is shared with the Guard via
`bin/lib/git-slots.sh`, so the two can never disagree.
_Avoid_: calling it enforcement (it only reports).

**Dedicated gh Config**:
A slot's own `gh` CLI config directory (`~/.config/gh-<name>`, mirroring
`~/.gitconfig-<name>`), bootstrapped once via `GH_CONFIG_DIR=~/.config/gh-<name>
gh auth login`. The `gh()` shell function (`home/.zsh_functions`) resolves the
current repo's bound slot on every invocation and re-execs the real `gh` with
that slot's dedicated config, so concurrent terminals on different slots never
race — replacing the single global active `gh` account (`gh auth switch`) that
ADR-0001 originally named as a known limitation. `dot git use`/`add-identity`
route through a slot's dedicated config when one exists, falling back to the
old global switch otherwise; `dot git gh-config-dir` prints the current repo's
dedicated config dir (used by the `gh()` wrapper, not usually run by hand).
_Avoid_: gh account, active account (those describe the older, superseded
global mechanism).

**Migration**:
The interactive one-pass onboarding (`dot git migrate`) that walks the same repos
as the Identity Audit (shared discovery in `bin/lib/git-repo-discovery.sh`) and, per mis-set
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

### Remote sessions

**Remote Session**:
The tmux session on a remote host that `srv` attaches to — created on first
connect and re-attached every time after (`tmux new-session -A`, one code path for
both). Its defining property is that it is **not owned by the ssh connection**:
detaching, losing wifi, or closing the laptop leaves it and everything running in
it alive on the host, and the next `srv` lands back in it. Named `main` unless a
second argument says otherwise, so "the Remote Session" for a host is singular by
default. Bounded by the host's uptime, not the laptop's — nothing in this repo
persists a session across a **reboot** of the host (no `tmux-resurrect`, by choice).
_Avoid_: "ssh session" (that is the connection, which is exactly the thing a Remote
Session is designed to outlive); "saved session" (nothing is written to disk — the
session is a live process that simply never had a client attached).

**Generated Remote Config**:
The rewritten copy of `config/tmux` that `srv-sync` ships to a host, at
`~/.config/tmux` there. It is **derived, never authored**: four constructs that
cannot work remotely are rewritten on the way out (`$DOTFILES` paths, the macOS
appearance probe, `pbcopy`, and the lazygit/`sesh` bindings), everything else stays
byte-identical so muscle memory carries over, and the whole tree is overwritten on
every sync. `srv-sync` hard-fails when a rewrite stops matching rather than
shipping a silently broken config, which makes the local `tmux.conf` the single
source of truth for both ends.
_Avoid_: editing the remote copy (it is overwritten); calling it a "remote
dotfiles install" (only tmux is synced, and only as generated output).
