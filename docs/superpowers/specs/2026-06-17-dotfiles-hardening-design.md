# Dotfiles Hardening & Restructure — Design

**Date:** 2026-06-17
**Status:** Approved (design); pending implementation plan
**Scope:** Harden the existing `dotfiles` repo in place across its whole lifecycle so it stops breaking, survives a hostile work laptop, and is well-tested.

---

## 1. Problem

The repo works "most of the time" but breaks across the entire lifecycle. The owner reports failures in **all four** of:

1. **Fresh-machine setup** — `setup.sh` aborts partway and leaves a half-configured machine.
2. **Daily shell health** — new terminals throw errors, slow startup, plugins silently not loading.
3. **Running updates** — `dot update` / brew / plugin updates silently break working state.
4. **Work vs personal drift** — the two laptops fall out of sync; work-laptop restrictions break personal-laptop assumptions.

The work laptop is **hostile**: MDM-managed with restricted admin, a different tool/app set, hard secret-isolation requirements, and a corporate proxy/cert environment.

### Root causes identified during brainstorming

- **`set -Eeuo pipefail` installer aborts on the first blocked step.** On the MDM/proxy work laptop, one blocked step kills the whole install and leaves a half-configured machine. This is the single biggest source of "fresh setup breaks."
- **No machine-profile model.** Work vs personal is half-solved with a single `HOMEBREW_DOCKER_RUNTIME` env var plus `~/.localrc`. Too thin to drive tool sets, identity, and per-step behavior.
- **Leftover cruft from a past oh-my-zsh era.** Untracked `config/zsh/` still holds `ohmyzsh/`, `.zcompdump*`, `.zsh_history`, `.zshrc.pre-oh-my-zsh`, `.DS_Store`. Generated runtime state living inside the repo tree keeps reappearing as debris.
- **No automated testing.** For a repo whose whole complaint is "it breaks," there is no CI and no test harness. `dot doctor` only checks an *already-configured* machine, not install logic or idempotency.

---

## 2. Goals

- Installer that **always completes** and **converges on re-run** — never leaves a half-configured machine.
- A real **machine-profile** system (`personal` | `work`) driving tools, identity, and optional steps.
- Survive **MDM + restricted admin + proxy**: every step degrades gracefully and reports why.
- Airtight **secret isolation** between work and personal.
- **Solid automated testing**: static checks + sandboxed behavior tests + idempotency, on free Linux CI.
- Every config is **crisp and deliberate** (no floated/copy-pasted defaults), plus a curated **tool shortlist** for the owner to approve.
- Keep the proven existing engineering: `bin/dot` manager, `dot doctor`, `lessons.md`.

## 3. Non-goals

- Ground-up rewrite of the repo (explicitly rejected — harden in place).
- Full toolchain redesign / mass tool replacement (only an approved shortlist of changes).
- Real macOS end-to-end install in CI (rejected as flaky/high-maintenance for partial confidence).
- Linux as a first-class target (macOS-only; Linux CI is a test substrate, not a supported install target).
- Cross-platform abstractions beyond what already exists in the Brewfile.

---

## 4. Decisions (locked during brainstorming)

| Question | Decision |
|----------|----------|
| Restructure aggressiveness | **Harden & restructure in place** (keep proven bones) |
| Failure modes to fix | **All four**: fresh setup, daily shell, updates, work/personal drift |
| Work-laptop constraints | **All four**: MDM/restricted admin, different tools, secret isolation, corporate proxy |
| Test depth | **Solid**: static + sandbox (bats) + idempotency, free Linux CI |
| Curation scope | **Audit + recommend a shortlist** (perfect existing configs; propose tool changes for approval) |
| Core architecture | **Option C — profile = intent, capability checks = resilience** |

### Core architecture: Option C

- **Profile = intent.** A single file `~/.config/dotfiles/profile` holds `personal` or `work`, chosen once and persisted. It decides *which* Brewfile bundle, git identity, app set, and optional steps apply.
- **Capability checks = resilience.** Every setup step is independently guarded (`command -v`, admin available?, network reachable?) and **non-fatal**: on failure it records the failure and continues. The run always completes and ends with a summary; re-running converges to a good state.

Rejected alternatives: pure capability detection (magic, untestable, can't express intent differences); pure explicit profiles with strict fail-fast (re-introduces the work-laptop abort problem).

---

## 5. Design

### 5.1 Profile system (spine)

- `~/.config/dotfiles/profile` — single line: `personal` | `work`.
- New `dot_profile()` helper in `bin/lib/common.sh` reads it (prompts once if unset in interactive setup; defaults to `personal` in `--non-interactive`).
- New `dot profile` subcommand: `dot profile [get|set <name>]`.
- Replaces the `HOMEBREW_DOCKER_RUNTIME` hack.

### 5.2 Brewfile split by profile

Currently one 69-line `Brewfile` mixing core CLI + casks + infra. Restructure into:

```
brew/
  Brewfile.core       # cross-profile CLI: git, zsh, fzf, ripgrep, nvim, k8s tools, …
  Brewfile.personal   # personal casks: docker-desktop, personal apps
  Brewfile.work       # corp: colima/rancher (no Docker Desktop license), VPN, Slack, company CLIs
```

- `dot homebrew bundle` reads the profile and runs **core + matching profile bundle**, each independently, so a blocked work cask never stops core CLI installs.
- Every entry keeps its trailing explanatory comment (existing rule).

> **Explicit restructure flag:** this moves `Brewfile` into `brew/` and splits it. Called out per the "don't move files without explicit instruction" rule; approving this spec is the explicit go-ahead.

### 5.3 Cruft removal + runtime-state relocation

- Delete untracked `config/zsh/` debris (`ohmyzsh/`, `.zcompdump*`, `.zsh_history`, `.zshrc.pre-oh-my-zsh`, `.DS_Store`).
- Relocate generated runtime state **permanently out of the repo tree**: `.zcompdump` → `$XDG_CACHE_HOME`, shell history → `$XDG_STATE_HOME`.
- Tighten `.gitignore` so this class of file cannot be committed again (zcompdump, ohmyzsh, history, `*.local`, `*-local`, SSH key patterns).

### 5.4 Resilient installer

Rewrite `setup.sh` into a **soft-failing step runner**:

- Each step is an isolated function returning `ok` / `skip(reason)` / `fail(reason)`. The runner captures failures and **keeps going**; the run always completes.
- **Idempotent:** every step detects "already done" and reports `skip (already configured)`. Re-running is safe and converging.
- **End-of-run summary:** table of `✓ ok` / `⊘ skipped (reason)` / `✗ failed (reason + one-line remediation)`. Exit non-zero only if a *required* step failed.
- **New flags:** `--profile work|personal`, `--non-interactive` (CI/tests), `--dry-run`.
- **Proxy/network hardening:** honor `HTTPS_PROXY`/`HTTP_PROXY`; wrap every curl-pipe installer (Homebrew, SDKMAN) with timeout + retry + skip-on-failure so a blocked fetch can't kill the run.
- Keep `set -u` / `set -o pipefail`; replace blanket `-e` abort with per-step error capture.

`dot update` gets the **same** soft-fail + idempotent + `--dry-run` treatment. `dot doctor` becomes **profile-aware** (knows which tools *should* exist for the active profile, so it detects work/personal drift).

### 5.5 Testing harness + CI

- **`tests/` using bats-core** (`bats-core` + `bats-support` + `bats-assert`). Each test points `HOME` at a throwaway temp dir, runs `dot link` / `backup` / `clean` against it, and asserts:
  - symlinks land correctly; backups are made; unlink/clean reverse cleanly;
  - **idempotency** — running twice yields no errors and no second-run changes (exit 0, no diff).
- **Unit tests** for `bin/lib/common.sh` helpers and pure logic in `dot-*` (profile resolution, Brewfile composition, tool-check derivation).
- **Static gates:** `shellcheck` (extend existing hook to all scripts) + `shfmt` + `zsh -n` on every rc file + a `zsh -i -c 'echo ok'` **smoke test** + Ruby syntax check on Brewfile bundles.
- **One entrypoint:** `dot test` (+ `just test` alias) runs lint + bats + smoke locally — the exact command CI runs.
- **CI: GitHub Actions on `ubuntu-latest`** (free, seconds). The `dot` manager is plain bash/symlinks, so sandbox + lint + smoke run on Linux. Genuinely macOS-only behavior (casks, `defaults write`) is documented as local-only, not faked.

### 5.6 Secrets isolation

- Standardize never-committed local files: `~/.gitconfig-local` (identity + signing key), `~/.zshrc.local` / `~/.localrc` (shell), `~/.zshenv.local` (env). Profile picks which identity is wired up.
- **Git conditional includes** (`includeIf "gitdir:~/work/"`) so work identity auto-applies in work repos and personal everywhere else — no manual switching, no cross-identity commits.
- **`gitleaks`** as a pre-commit hook *and* a CI job — a work token/key can never be committed.

### 5.7 Config audit + tool shortlist (deliverables)

Produced during implementation, before any churn:

- `docs/audit/config-audit.md` — every config (zsh, starship, nvim, tmux, aerospace, ghostty, git, …) reviewed for floated/default-copy settings, dead config, fragile patterns, best-practice gaps, with concrete fixes.
- `docs/audit/tool-shortlist.md` — gaps/additions/replacements with rationale. **No tool-lineup change ships without owner sign-off** on this list.

---

## 6. Implementation phases

Each phase is independently shippable and testable.

1. **Cruft cleanup + state relocation + `.gitignore`** — immediate stability win.
2. **Profile system** — `~/.config/dotfiles/profile`, `dot_profile()` helper, `dot profile` subcommand.
3. **Brewfile split** — `brew/Brewfile.{core,personal,work}`; `dot homebrew bundle` composes by profile.
4. **Resilient installer + `dot update`/`dot doctor` refactor** — soft-fail step runner, summary, flags, proxy hardening, profile-aware doctor.
5. **Testing harness + CI + gitleaks** — bats sandbox/idempotency tests, static gates, `dot test`, GitHub Actions, secret scanning.
6. **Config audit + tool shortlist** — the two deliverable docs → then implement owner-approved changes.

---

## 7. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Restructure breaks current working machine | Phase 1 first (pure cleanup, no behavior change); each phase tested before merge; `dot backup` before linking. |
| bats tests pass on Linux but real break is macOS-only | Keep `zsh -i -c` smoke + lint; document macOS-only steps; rely on `dot doctor` locally for cask/defaults. |
| Soft-fail installer hides a genuinely fatal problem | Distinguish *required* vs *optional* steps; required failures set non-zero exit and are surfaced loudly in the summary. |
| Brewfile split drifts from reality | Ruby syntax check in CI; `dot doctor` is profile-aware and flags missing/extra tools. |
| Secret leak during restructure | `gitleaks` pre-commit + CI before any other phase merges; `.gitignore` guards added in Phase 1. |

---

## 8. Success criteria

- `setup.sh` on a fresh machine **always completes** with a clear summary; re-running is a clean no-op (all `skip`).
- On the work laptop, blocked steps are **skipped with reasons**, not fatal; core CLI tools still install.
- `dot test` and CI are **green**; bats proves link/backup/clean correctness and idempotency.
- New terminals open with **zero errors** (`zsh -i -c 'echo ok'` clean).
- Work and personal identities/tools are driven by **profile**; no manual switching; no committed secrets.
- Every config file is deliberate (audit doc has no open "floated default" findings); tool changes are owner-approved.
