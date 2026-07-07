# Dotfiles

Personal dotfiles for a macOS work laptop. This glossary pins down terms that are
specific to this repo's conventions — not general shell/git concepts.

## Language

### Git identity

**Identity Slot**:
A named git identity bundled as a set that always travels together — an SSH
key (used for both auth _and_ commit signing via `gpg.format=ssh`), an SSH host
alias that selects that key, and a gitconfig fragment carrying the commit email
and signing config. A slot is keyed by **account**, not by org — one slot spans
every org that account can reach (e.g. the `ee` slot covers EE-corp _and_ any
client org that simply adds your EE account). A client becomes its **own** slot
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
