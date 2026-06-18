# Dotfiles Config Fit-to-Stack — Implementation Plan (Plan 12)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make the prompt, terminal, ignore, and CLI configs fit the owner's Java/K8s/Terraform stack — the remaining high/med fit-to-stack items from the audit (`config-audit.md` §3/§4/§5) that weren't safety fixes (those shipped in Plan 9).

**Architecture:** Config-only edits (toml/conf/yaml/gitignore). Verified statically — `check-toml` (starship/sesh), `git check-ignore` (gitignore), `tmux -f … new-session -d` parse check, and `nvim --headless +qa` is unaffected. The audit §3/§4/§5 carry the detailed per-item fixes; this plan groups them.

## Global Constraints
- macOS-only; Apple Silicon. Conventional Commits; no `Co-Authored-By`. `bin/dot test` + CI stay green (these configs aren't exercised by the bash gate, but run it to confirm no collateral).
- Don't break the active catppuccin theming / existing keybindings; make surgical edits and keep each config's section structure.
- Reference spec: `docs/audit/config-audit.md` §3 (terminal), §4 (aerospace+starship), §5 (git+CLI). Read the relevant section before each task.

## File Structure
- `config/starship/starship.toml` — **Modify** (Task 1).
- `config/git/ignore`, `config/ripgrep/config` — **Modify** (Task 2).
- `config/tmux/tmux.conf`, `config/ghostty/config`, `config/lazygit/config.yml`, `config/aerospace/aerospace.toml` — **Modify** (Task 3).

---

## Task 1: Starship — Terraform, K8s, Kotlin, timeouts

Covers config-audit §4 starship items (#7–#13).

- [ ] **Step 1: Apply the starship fixes** (read §4 first)
  - Add a `$terraform` module to the `format` string + a `[terraform]` block (compact `\[[ $workspace]($style)\]`, an `#f5a97f`-ish style) — Terraform workspace visibility.
  - Kubernetes `[kubernetes]`: remove the no-op `detect_files` `"k8s"`/`"kubernetes"` (they match files, not dirs); either always-show (`disabled = false`, no detect_files) or use `detect_folders`/real triggers. Add `context_from_config = true` to avoid the `kubectl` binary call on slow VPN, and raise `command_timeout` to `2000`.
  - `[kotlin]`: `disabled = true` (no Kotlin in the stack; lights up on Gradle-Kotlin projects).
  - Add explicit compact `[aws]` (and `[gcloud]` if relevant) config OR explicitly `disabled = true` — so they don't appear unexpectedly when env vars are set.
  - `username`/`hostname`: either add `$username$hostname` to the format (useful over SSH) OR remove the dead config blocks. Pick one and note it.
  - Consider `[gradle]` `disabled = true` (redundant with `[java]`) — note the choice.

- [ ] **Step 2: Verify + commit**

Run: `pre-commit run check-toml --files config/starship/starship.toml` → Passed (it's `.toml`). If starship is installed: `starship config 2>&1 | head` / `STARSHIP_CONFIG=config/starship/starship.toml starship prompt 2>&1 | head` parses without error.
Run: `bin/dot test` → `All checks passed`.

```bash
git add config/starship/starship.toml
git commit -m "feat(starship): add terraform module, fix k8s trigger, trim noise"
```

---

## Task 2: Global gitignore + ripgrep types

Covers config-audit §5 #13/#14 (gitignore) + #15 (ripgrep).

- [ ] **Step 1: Add Java/Spring/Terraform/IntelliJ entries to `config/git/ignore`**
  - Add: `.idea/`, `*.iml`, `*.ipr`, `*.iws` (IntelliJ); `target/`, `build/`, `.gradle/`, `!gradle/wrapper/gradle-wrapper.jar` (Java/Gradle/Maven); `.terraform/`, `*.tfstate`, `*.tfstate.*`, `.terraform.lock.hcl` is usually committed (do NOT ignore it), `crash.log`, `*.tfvars` only if they hold secrets (note — leave `.tfvars` commitable, just ignore `*.auto.tfvars` if appropriate); `.DS_Store` (confirm present).
  - Remove the stale vim/coc lines (`.vimrc.local`, `.vim/coc-settings.json`).

- [ ] **Step 2: Update ripgrep types in `config/ripgrep/config`**
  - Remove the JS/TS/pug/graphql/stories `--type-add` lines.
  - Add (if not built-in): `--type-add=gradle:*.{gradle,gradle.kts}`, `--type-add=tf:*.{tf,tfvars}`. (java/kotlin/yaml are built-in rg types.)

- [ ] **Step 3: Verify + commit**

Run: `git check-ignore -v target .idea/x .terraform/y build foo.iml | wc -l` → matches the new rules (expect ≥5).
Run: `rg --type-list 2>/dev/null | grep -E "gradle|tf:" || true` is informational. `bin/dot test` → green. `pre-commit run --all-files` → all Passed.

```bash
git add config/git/ignore config/ripgrep/config
git commit -m "feat(config): gitignore and ripgrep types for Java/Terraform/IntelliJ"
```

---

## Task 3: Terminal true-color + lazygit + aerospace

Covers config-audit §3 (tmux/ghostty) + §5 (lazygit) + §4 (aerospace numbered-workspace cleanup).

- [ ] **Step 1: tmux true-color + ergonomics** (config-audit §3 T1–T13, X1)
  - `default-terminal "tmux-256color"` (not `${TERM}`); `set -as terminal-features ",xterm-ghostty:RGB:usstyle"` (true-color + undercurl inside Ghostty).
  - `escape-time 10` (not 0); `window-size latest` (replace deprecated `aggressive-resize`).
  - copy-mode-vi: add `bind -T copy-mode-vi y send -X copy-pipe-and-cancel "pbcopy"`.
  - `bind r source-file "$DOTFILES/config/tmux/tmux.conf"` (not hardcoded `~/.config`).
  - Remove the dead commented sesh block remnants / unused `default.conf`/`bubbles.conf` references if present; remove the double `send-prefix` bind.

- [ ] **Step 2: ghostty cleanups** (config-audit §3 G1, G3, G4)
  - De-dupe `shell-integration-features` (keep one line); remove `window-decoration = true` (no-op on macOS) and the default padding zeroes.

- [ ] **Step 3: lazygit** (config-audit §5 #18–#23)
  - `os.editPreset: "nvim"` (jump-to-line). Remove the deprecated empty `os.*` fields, the deprecated log fields, and `showIcons: false`.

- [ ] **Step 4: aerospace numbered-workspace cleanup** (config-audit §4 #4, #6)
  - Remove the 18 dead `alt-1..9` / `alt-shift-1..9` numbered-workspace bindings (the named-workspace model is the intended workflow) — OR keep if you use them; default to removing per the audit. Remove the empty `after-login-command`/`after-startup-command` lines. Add float rules for Activity Monitor/Console.

- [ ] **Step 5: Verify + commit**

Run: `pre-commit run check-toml --files config/aerospace/aerospace.toml` → Passed.
Run (tmux parse, if available): `tmux -f config/tmux/tmux.conf new-session -d -s _v \; kill-session -t _v 2>&1 && echo TMUX_OK`.
Run: `python3 -c "import yaml; yaml.safe_load(open('config/lazygit/config.yml')); print('LG_YAML_OK')"`.
Run: `bin/dot test` → green; `pre-commit run --all-files` → all Passed.

```bash
git add config/tmux/tmux.conf config/ghostty/config config/lazygit/config.yml config/aerospace/aerospace.toml
git commit -m "feat(terminal): true-color tmux/ghostty, lazygit nvim editor, trim aerospace"
```

---

## Done criteria
- Starship shows Terraform workspace + reliable K8s context; Kotlin/AWS noise gated; timeouts raised.
- Global gitignore covers Java/Spring/Terraform/IntelliJ; ripgrep types fit the stack.
- tmux/ghostty render true-color + undercurl correctly (`tmux-256color` + RGB feature); lazygit edits in nvim with jump-to-line; aerospace dead bindings trimmed.
- `bin/dot test` and both CI jobs green; all touched toml/yaml validate.

> Plan 13 (final): the remaining low-severity polish sweep (the §1 zsh dead-config removals, lazygit log-cmd cosmetics, README dup heading, broadening shellcheck to legacy bin/, etc.).
