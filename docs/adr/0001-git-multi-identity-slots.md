# Git multi-identity via remote-bound slots with a blocking guard

## Context

This is a consultancy work laptop (Equal Experts). Multiple git identities coexist
and the set changes over time: `personal` (github.com/chiyanram), `ee`
(github.com, `@equalexperts.com`), and one identity per client engagement — all
currently on github.com, i.e. the same-host, multiple-account case. The danger is
not auth failure but **misattribution**: a commit stamped with the wrong email,
especially one client's email landing in another client's or a public personal
repo. Relying on the developer to remember to configure each repo was judged
certain to fail eventually.

## Decision

Model each identity as an **Identity Slot** — an SSH key + a `<host>-<name>` SSH
**alias** that selects it + a gitconfig fragment with the email. A repo's remote
URL names the slot, and **both key and email follow from that name**:

- SSH `Host <host>-<name>` aliases route the key (same host, different key per account — required because GitHub rejects one key on two accounts).
- Each slot **signs** commits with its own SSH key (`gpg.format=ssh`, `commit.gpgsign=true` in the slot fragment), so every commit is verified under the correct identity. The auth key doubles as the signing key. (GitHub nuance: the same public key must be registered *twice* on the account — once as an Authentication key, once as a Signing key — or signatures show "Unverified".)
- `includeIf "hasconfig:remote.*.url:git@<host>-<name>:*/**"` **binds** the email to that alias, so email cannot drift from key (git 2.36+; we run 2.55). (The path glob is `*/**`, not a bare `:**` — git's hasconfig `**` only crosses a `/` when slash-delimited, so a bare `:**` never matches an scp URL's `owner/repo` path.)
- The **fallback identity** in `~/.gitconfig-local` is `personal`, used only when no slot matches (e.g. a remote-less scratch repo) — chosen so a forgotten repo commits harmlessly as the user, never as the wrong client. (This also fixes prior drift where `~/.gitconfig-local` wrongly held the EE email.)
- An **Identity Guard** `pre-commit` hook (global `core.hooksPath`) enforces it: a commit to a repo whose remote is on a *known host* with *no matching slot* is **blocked**, printing the exact `dot git use <slot>` / `dot git add-identity` command to run. Repos with no remote (scratch) are allowed. **The guard is the correctness mechanism (zero-config, any repo, any time); `dot doctor` is only a convenience sweep.** `dot doctor` runs the same check in bulk over a hardcoded set of conventional roots that exist (`~/work`, `~/workspace`, `~/dev`, `~/dotfiles`, `~/personal`, `~/clients`), with an optional `git_audit_roots` override — no bootstrap prompt, no memory burden, because a missed root only means the sweep skips it, not that its commits are unprotected.
- A slot also owns its **`gh` (GitHub CLI) account**: `dot git use <slot>` runs `gh auth switch` to align the active `gh` login (closing the PR/issue attribution gap the git-only guard can't see), and `dot doctor` warns when the active `gh` account mismatches the repo's slot. The **git-side of a slot (key, email, signing, guard) is host-agnostic** — GitLab/Bitbucket clients work fully; only the CLI-account sync is GitHub-only and is a silent no-op on other hosts (`glab` support deferred).
- `dot git add-identity --name <n> --host <h> --email <e>` builds a whole slot (key, alias, fragment, signing, `hasconfig` line) in one command; `dot git use <slot>` binds the current repo to a slot; `dot git migrate` interactively walks `dot doctor`'s findings, binding each existing mis-set repo to a slot in one pass (adoption-day bulk cleanup; the guard backstops the rest); `dot git remove-identity <slot>` tears a slot down symmetrically (removes alias/fragment/includeIf, shreds the local key, reminds you to revoke it on the client's GitHub, warns if any local repo still uses the alias). Onboarding *and* offboarding a client are each one command — offboarding is first-class because stale client keys are a compliance hazard.

## Considered options

- **Fallback = current client (EE)** instead of personal — rejected: on a rotating-client laptop a forgotten new-client repo would inherit the *previous* client's email, the worst leak.
- **Guard auto-fixes the remote** instead of block-and-guide — rejected: silently rewriting `origin` is surprising, and a plain remote URL (`git@github.com:acme/api`) does not unambiguously reveal which slot to use, so the choice stays with the developer via one command.
- **Warn-only guard** — rejected: a warning is still manual and reintroduces the silent-miss failure it exists to prevent.
- **HTTPS + credential routing** instead of SSH aliases — rejected: macOS `osxkeychain` stores one token per host, so two github.com accounts collide.
- **Directory-based scoping** (`~/work/`) instead of remote-based — rejected: personal repos (e.g. dotfiles in `~/dotfiles`) don't sit under one tree, and directory scoping doesn't bind auth to identity.

- **Key hygiene:** every slot key is passphrase-protected, cached once via the macOS keychain (`AddKeysToAgent`/`UseKeychain` in a `Host *` ssh block; `ssh-add --apple-use-keychain`). The existing `id_ed25519` (currently unencrypted, and tied to the **EE** account) becomes the `ee` slot key — renamed `id_ed25519_ee` and re-encrypted with a passphrase; a fresh `id_ed25519_personal` is generated for the personal account (which has no key on this laptop today, since dotfiles uses HTTPS).

## Consequences

- Every managed repo must use an aliased remote (`dot git use <slot>` converts a plain clone). The one irreducibly manual step is pasting each slot's public key into its own account.
- Slot names, client emails, and keys are per-machine/per-engagement and live in generated, **un-committed** files (`~/.ssh/config` blocks, `~/.gitconfig-<slot>`, `~/.gitconfig-identities`); the shared `config/git/config` only gains a neutral `include` — honoring the rule that identity/auth never enters version control.
- **`gh` active account is global**, so the last `dot git use` wins across terminals; two concurrent client sessions in two terminals can still mis-fire. Accepted for now (`dot doctor` catches it); true per-terminal isolation would need per-slot `GH_CONFIG_DIR` env, deferred.
- **Known limitation (SSH-first):** the slot routes auth via an SSH host-alias, so a client that forbids SSH (HTTPS-only egress) is not supported yet. If one appears, the slot abstraction grows an HTTPS variant (email still bound by URL-path pattern; auth via a per-slot credential route) — deferred, not built, to avoid speculatively solving the two-token HTTPS collision.
