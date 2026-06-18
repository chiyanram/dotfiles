# Tool Shortlist — 2026-06-18 (for your approval)

Curated tool recommendations for a senior Java / Spring Boot / Gradle / PostgreSQL / Kubernetes / Terraform backend engineer on macOS (Apple Silicon) who also tracks the Indian stock market. **Nothing changes the Brewfile without your sign-off** — tick what you want and I'll add it (to `core`/`personal`/`work` as noted).

**Already installed** (not re-recommended): jq, yq, fzf, fd, ripgrep, bat, eza, zoxide, procs, btop, lazygit, gh, git-delta, glow, just, direnv, fnm, entr, pgcli, kubectl, kubectx, k9s, helm, stern, httpie, jbang, dive, lazydocker, kubecolor, starship, neovim, tmux, sesh.

---

## Top 8 — if you only add a few (ranked by impact ÷ effort for your stack)

| # | Tool | Why | Where |
|---|------|-----|-------|
| 1 | **atuin** | SQLite-backed, searchable, context-aware shell history (dir, exit code, duration) with optional self-hosted sync. Biggest daily quality-of-life lift. | core |
| 2 | **tenv** | Unified version manager for Terraform/OpenTofu/Terragrunt; honors `.terraform-version`. Replaces manual TF install + tfswitch. | core |
| 3 | **kubeconform** | Validates K8s manifests against API schemas before `kubectl apply` (maintained successor to kubeval). | core |
| 4 | **trivy** | One scanner for container images, IaC, filesystems, SBOMs. Closes the security gap given Docker+TF+K8s. | core |
| 5 | **git-absorb** | Auto-creates `fixup!` commits against the right prior commit. Removes the most tedious rebase step. | core |
| 6 | **tflint** | Terraform linter that catches what `terraform validate` can't (provider-specific mistakes). | core |
| 7 | **fx** | Interactive JSON browser — exploration (vs `jq` for scripting). Constant use with K8s/API output. | core |
| 8 | **grpcurl** | `curl` for gRPC — the ergonomic way to poke gRPC services (increasingly common with Spring Boot). | core |

---

## Full additions menu

### Infrastructure / Kubernetes
- **kustomize** (core) — standard K8s overlay tool, separate from Helm; standalone install stays current vs `kubectl kustomize`.
- **kubeconform** (core) — see top-8.
- **tenv** (core) — see top-8.
- **tflint** (core) — see top-8.
- **trivy** (core) — see top-8.
- **terraform-docs** (work) — generates module README tables; standard in shared-module teams.
- **argocd** (work) — only if you run ArgoCD; CLI for sync/rollback/diff.

### Java / backend
- **google-java-format** (core) — opinionated zero-config Java formatter; plugs into pre-commit (pairs with the nvim conform work).
- **gradle-profiler** (personal/work) — benchmarks/build-scans Gradle when builds slow down.
- **hyperfine** (core) — CLI benchmarking (Gradle tasks, startup times); fits the "measure everything" posture.

### Data / API
- **grpcurl** (core) — see top-8.
- **fx** (core) — see top-8.
- **usql** (personal) — universal SQL CLI (Postgres/MySQL/SQLite/…); complements `pgcli` for ad-hoc other-DB work.

### Shell / productivity
- **atuin** (core) — see top-8.
- **git-absorb** (core) — see top-8.
- **difftastic** (core) — AST-aware structural diff (Java/YAML/HCL/Lua); use alongside delta (delta = line diff, difftastic = semantic review).
- **sd** (core) — simpler find/replace than `sed` (an explicit alternative, not an alias — respects your no-POSIX-alias rule).
- **navi** (personal) — interactive cheatsheet browser (fzf-backed) for your kubectl/terraform one-liners.
- **miller / mlr** (personal) — awk/sed for CSV/TSV/JSON; useful for stock/MF CSV exports and portfolio data.
- **presenterm** (personal) — markdown terminal slideshows (vs glow for reading) if you do internal talks.

---

## Possible replacements / upgrades (read the tradeoff)

- **mise** vs **SDKMAN + fnm** — `mise` unifies Java/Node/Python/… version management with per-dir `.mise.toml`. **Verdict: stay with SDKMAN + fnm** — SDKMAN's Java-distribution awareness (Temurin/Corretto/GraalVM, `sdk env`) is deeper and you're a Java-25-primary user. Revisit only if the dual-manager UX becomes painful.
- **watchexec** vs **entr** — watchexec is more ergonomic for multi-file/recursive patterns (`watchexec -e java -- ./gradlew test`). Low-priority swap; keep `entr` for simple one-liners.
- **yazi** (personal, low urgency) — full async TUI file manager; a different paradigm from your `zoxide`+`eza`+`fzf` flow. Add only if you want a visual file browser.
- **bottom** vs **btop** — no meaningful advantage; **skip** (btop is great).

---

## Profile placement (move out of `core`?)

- **dive**, **lazydocker** — Docker-dependent; dead weight on a fresh machine before Docker is installed. → move to `personal` + `work` (both set up a Docker runtime). *Clearest candidates to move.*
- **pgcli** — Postgres-specific; defensible in `core` since PostgreSQL is your primary DB, but could be `personal`+`work` if a locked-down work env has no Postgres access.
- **fnm** — if a work machine has a corporate Node toolchain, consider `personal`-only.
- Everything else in `core` is broadly justified (jbang/kubecolor/stylua are tied to Java/K8s/nvim which are universal to your work).

---

## How I'll proceed

Tell me which of these you want (e.g. "add the top 8 to core; move dive+lazydocker to personal/work; skip the rest") and I'll:
1. Add the approved entries to the right `brew/Brewfile.*` with trailing comments (and move the placement ones).
2. Run `brew bundle` validation + the gate.
3. The Java/Terraform/YAML tooling here pairs with the nvim `jdtls`/`terraformls`/`yamlls` work in the config audit — I can sequence them together.
