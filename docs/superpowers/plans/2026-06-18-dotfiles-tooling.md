# Dotfiles Tooling — Implementation Plan (Plan 10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the approved tools (`docs/audit/tool-shortlist.md`) to the profile Brewfiles, move Docker-only tools out of core, commit to **sesh** (real config + retire the custom `tm` script), and remove the dead legacy `bin/` scripts.

**Tech Stack:** Homebrew Bundle, sesh/tmux, bash/zsh, bats.

## Global Constraints
- macOS-only; Linux CI substrate. Brewfile: organized by category with comments; every entry has a trailing comment; casks inside `if OS.mac?`.
- `dot-*`/bash: `set -Eeuo pipefail`; shfmt -i 2 -ci + shellcheck-clean. Conventional Commits; no `Co-Authored-By`.
- `bin/dot test` + CI stay green. (Brewfiles are validated by `ruby -c` + `dot_brewfiles`; tools are NOT installed by this plan — only listed.)

## File Structure
- `brew/Brewfile.core`, `brew/Brewfile.personal`, `brew/Brewfile.work` — **Modify**: add approved tools; move `dive`/`lazydocker` out of core.
- `config/sesh/sesh.toml` — **Modify**: real config (zoxide default, fixed blacklist, documented session example).
- `config/tmux/tmux.conf` — **Modify**: `bind s` → sesh popup; remove the dead commented sesh block.
- `bin/tm` — **Remove** (retired in favor of sesh).
- `bin/t`, `bin/update`, `bin/battery`, `bin/hl` — **Remove** (dead per audit).
- `bin/git-clc` — **Modify**: fix the `--apprev-ref` typo.

---

## Task 1: Brewfile tool additions + placement

**Files:** `brew/Brewfile.core`, `brew/Brewfile.personal`, `brew/Brewfile.work`

- [ ] **Step 1: Verify formula names exist (avoid a bad entry)**

Run for each new formula to confirm it's in Homebrew (skip-on-fail, just to catch typos):
```bash
for f in kustomize kubeconform tenv tflint trivy google-java-format hyperfine grpcurl fx atuin git-absorb difftastic sd usql navi miller presenterm gradle-profiler terraform-docs argocd; do
  brew info "$f" >/dev/null 2>&1 && echo "OK   $f" || echo "MISSING $f"
done
```
For any `MISSING`, check the real name (`brew search`) and use it, or drop it with a note in the report.

- [ ] **Step 2: Add the core tools to `brew/Brewfile.core`**

Add to `brew/Brewfile.core`. Put k8s/infra entries in the Infrastructure section, dev tools in Development tools — each with a trailing comment:

```ruby
brew 'kustomize'                       # Kubernetes config overlays (non-Helm)
brew 'kubeconform'                     # validate K8s manifests against API schemas
brew 'tenv'                            # Terraform/OpenTofu/Terragrunt version manager
brew 'tflint'                          # Terraform linter (catches provider mistakes)
brew 'trivy'                           # security scanner: images, IaC, SBOMs
brew 'google-java-format'              # opinionated zero-config Java formatter
brew 'hyperfine'                       # CLI benchmarking (Gradle tasks, scripts)
brew 'grpcurl'                         # curl for gRPC services
brew 'fx'                              # interactive JSON browser (vs jq for scripting)
brew 'atuin'                           # searchable, synced shell history
brew 'git-absorb'                      # auto fixup! commits into the right prior commit
brew 'difftastic'                      # AST-aware structural diffs (alongside delta)
brew 'sd'                              # simpler find/replace than sed (not a POSIX alias)
```

- [ ] **Step 3: Add personal/work tools + move Docker tools**

In `brew/Brewfile.core`, REMOVE the `dive` and `lazydocker` lines (they're Docker-only).

In `brew/Brewfile.personal`, add:
```ruby
brew 'dive'                            # Docker image layer analyzer
brew 'lazydocker'                      # Docker TUI
brew 'usql'                            # universal SQL CLI (Postgres/MySQL/SQLite)
brew 'navi'                            # interactive cheatsheet browser
brew 'miller'                          # awk/sed for CSV/TSV/JSON (stock/MF exports)
brew 'presenterm'                      # markdown terminal slideshows
brew 'gradle-profiler'                 # benchmark/profile slow Gradle builds
```

In `brew/Brewfile.work`, add:
```ruby
brew 'dive'                            # Docker image layer analyzer
brew 'lazydocker'                      # Docker TUI
brew 'terraform-docs'                  # generate Terraform module README tables
brew 'argocd'                          # ArgoCD GitOps CLI
```

(If any formula was `MISSING` in Step 1, omit it and note it.)

- [ ] **Step 4: Validate**

Run: `bats tests/brewfiles.bats` (ruby syntax) and `bats tests/brew_helpers.bats`
Expected: pass.

Run: `bin/dot test`
Expected: `All checks passed`.

- [ ] **Step 5: Commit**

```bash
git add brew/
git commit -m "feat(brew): add approved tools and move Docker tools out of core"
```

---

## Task 2: Commit to sesh; retire `tm`

**Files:** `config/sesh/sesh.toml`, `config/tmux/tmux.conf`, remove `bin/tm`

- [ ] **Step 1: Write a real sesh config**

Replace `config/sesh/sesh.toml` with:

```toml
# sesh — smart tmux session manager (zoxide-ranked). https://github.com/joshmedeski/sesh

# Hide noise directories from the picker (** = recursive).
blacklist = ['~/.local/share/**', '~/.cache/**', '~/.Trash/**']

[default_session]
startup_command = ""

# Add frequent projects here for one-keystroke startup, e.g.:
# [[session]]
# name = "dotfiles ⚙️"
# path = "~/tools-repo/dotfiles"
# startup_command = "nvim"
```

- [ ] **Step 2: Point tmux `bind s` at sesh**

In `config/tmux/tmux.conf`, remove the commented-out sesh block (the `# bind-key "s" display-popup ...` lines) and replace the active `bind s display-popup -E "tm"` line with an fzf-driven sesh popup:

```tmux
# Session switcher — sesh (zoxide-ranked) via fzf popup
bind s display-popup -E -w 60% -h 60% "sesh connect \"\$(sesh list -i | fzf --reverse --no-sort --prompt='⚡ ')\""
```

- [ ] **Step 3: Retire the `tm` script**

Confirm nothing else references `tm`:
```bash
grep -rn '\btm\b' config/ home/ bin/dot* setup.sh 2>/dev/null | grep -v 'tmux\|sesh.toml\|Brewfile' || echo "no other tm refs"
```
Then remove it: `git rm bin/tm`.
(If the grep shows a real reference outside the tmux binding you just changed, update it to use sesh and note it.)

- [ ] **Step 4: Validate**

Run: `pre-commit run check-toml --files config/sesh/sesh.toml` → Passed.
Run: `bin/dot test` → `All checks passed` (tm removal doesn't affect the gate; `bin/dot-*` glob is unaffected since `tm` has no `dot-` prefix).
Run (tmux config sanity, if tmux available): `tmux -f config/tmux/tmux.conf new-session -d -s _validate \; kill-session -t _validate 2>&1 && echo TMUX_OK || echo "tmux validate skipped"`

- [ ] **Step 5: Commit**

```bash
git add config/sesh/sesh.toml config/tmux/tmux.conf
git rm bin/tm
git commit -m "feat(sesh): adopt sesh as the session manager and retire tm"
```

---

## Task 3: Remove dead `bin/` scripts + fix `git-clc`

**Files:** remove `bin/t`, `bin/update`, `bin/battery`, `bin/hl`; modify `bin/git-clc`

- [ ] **Step 1: Confirm the dead scripts are unreferenced**

```bash
for s in t update battery hl; do
  echo "== $s =="
  grep -rn "\b$s\b" config/ home/ bin/dot* setup.sh bootstrap.sh 2>/dev/null | grep -vE "\.git/|docs/" | head
done
```
`battery` may appear only in a COMMENTED tmux theme line — that's fine (it's dead). `update` may appear in docs/comments. If any is actively used (uncommented), STOP and report instead of removing.

- [ ] **Step 2: Remove the dead scripts**

```bash
git rm bin/t bin/update bin/battery bin/hl
```
If `battery` is referenced in a commented tmux theme line, also delete that comment line in the theme file.

- [ ] **Step 3: Fix the `git-clc` typo**

In `bin/git-clc`, fix `--apprev-ref` → `--abbrev-ref`:

```zsh
[[ -z $1 ]] && BRANCH=$(git rev-parse --abbrev-ref HEAD) || BRANCH=$1
```

- [ ] **Step 4: Validate**

Run: `zsh -n bin/git-clc && echo GITCLC_OK`
Run: `bin/dot test` → `All checks passed`.
Run: `pre-commit run --all-files` → all Passed/Skipped.

- [ ] **Step 5: Commit**

```bash
git add bin/git-clc
git commit -m "chore(bin): remove dead scripts and fix git-clc branch typo"
```

---

## Done criteria
- All approved tools are in the right `brew/Brewfile.*` with trailing comments; `dive`/`lazydocker` moved to personal+work; Brewfiles pass `ruby -c`.
- sesh has a real config (zoxide-ranked, fixed blacklist); tmux `bind s` opens sesh; `bin/tm` is gone.
- Dead `bin/` scripts (`t`, `update`, `battery`, `hl`) removed; `git-clc` typo fixed.
- `bin/dot test` and both CI jobs green.

> Deferred to Plan 13 (polish): broadening the shellcheck lint gate to cover the remaining legacy `bin/` utilities (complicated by zsh scripts shellcheck can't lint) + their mechanical fixes.
