# Dotfiles Profile System — Implementation Plan (Plan 2 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the machine-profile spine — a persisted `personal`|`work` profile plus per-machine config (`work_dir`, `docker_runtime`) — exposed through `common.sh` helpers and a `dot profile` command, so Plans 3–4 can drive the Brewfile split, identity, and installer off it.

**Architecture:** Two tiny state files under `$XDG_CONFIG_HOME/dotfiles/` (`profile` = one word; `config` = `key=value` lines). Pure read/write helpers live in `bin/lib/common.sh` (already sourced by every script). `bin/dot-profile` is a thin CLI over those helpers, auto-discovered by `bin/dot` via the existing `dot-*` PATH dispatch and auto-gated by the Plan 1 lint surface (which globs `bin/dot-*`).

**Tech Stack:** bash, bats-core.

## Global Constraints

Copied verbatim from the spec (`docs/superpowers/specs/2026-06-17-dotfiles-hardening-design.md` §5.1) and `CLAUDE.md`. Every task implicitly includes these.

- macOS-only target; Apple Silicon `/opt/homebrew` with Intel `/usr/local` fallback. Linux CI is a test substrate only.
- All bash scripts start with `set -Eeuo pipefail` and source `$DOTFILES/bin/lib/common.sh`.
- In functions use `return 1`, never `exit 1`. Never use `trap EXIT` inside a function.
- macOS BSD tools: no `readlink -f`, no GNU `sed -i`. Rewrite files via a `mktemp` + `mv` temp-file pattern.
- Day-0 safe: guard files with `[[ -f ]]`, dirs with `[[ -d ]]`; helpers must work when the profile/config files do not exist yet.
- `dot-*` scripts have a `# Description:` comment on line 2; use `log_*` / `fmt_*` helpers from `common.sh`.
- Shell indent 2 spaces; format with `shfmt -i 2 -ci`. All maintained scripts stay shellcheck-clean (the Plan 1 gate runs `shellcheck`/`shfmt` over `bin/dot`, every `bin/dot-*`, `bin/lib/*.sh`, `setup.sh`, `bootstrap.sh`).
- Profile value set is exactly `personal` | `work`; default when unset is `personal`.
- Config keys are `key=value` lines; values may contain `=`; the first `=` separates key from value.
- Per-machine state path: `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/` — files `profile` and `config`. Never committed.
- Conventional Commits; imperative, lowercase, ≤72 chars. No `Co-Authored-By`.
- `bin/dot test` and CI (`checks` + `pre-commit`) must stay green.

---

## Plan Roadmap (where this fits)

Plan 1 (foundation) is merged. This is Plan 2. It establishes profile state + helpers + the `dot profile` command only. Deliberately OUT of scope (later plans consume this spine):
- Brewfile split / `docker_runtime` consumption → Plan 3.
- `setup.sh` prompting for the profile, profile-aware `dot doctor`, git conditional-include from `work_dir` → Plan 4 / Plan 5.

Nothing here changes `setup.sh`, the Brewfile, or `dot doctor`; a missing profile file simply defaults to `personal`, so nothing breaks before the consumers land.

---

## File Structure (Plan 2)

- `bin/lib/common.sh` — **Modify**: add a "Profile / machine config" section with `dot_profile`, `dot_set_profile`, `dot_config`, `dot_set_config`.
- `bin/dot-profile` — **Create**: the `dot profile` CLI (`get` / `set` / `set-config` / `show` / `--help`).
- `tests/profile_helpers.bats` — **Create**: bats tests sourcing `common.sh` and exercising the four helpers in a sandbox.
- `tests/dot_profile.bats` — **Create**: bats tests invoking the `bin/dot-profile` CLI in a sandbox.
- `README.md` — **Modify**: document `dot profile` under the commands section.

---

## Task 1: Profile + config helpers in `common.sh`

Add four pure read/write helpers. They are the single source of truth for profile/config state; `dot-profile` (Task 2) and later plans consume them. Built test-first against bats.

**Files:**
- Create: `tests/profile_helpers.bats`
- Modify: `bin/lib/common.sh` (add a new section before the final `setup_colors` call on the last line)

**Interfaces:**
- Produces (sourced from `common.sh`):
  - `dot_profile()` → prints `personal` or `work` (defaults to `personal` when the file is missing/empty/invalid). Exit 0.
  - `dot_set_profile <name>` → validates `name ∈ {personal, work}`, writes `$XDG_CONFIG_HOME/dotfiles/profile`. Returns 1 + `log_error` on invalid name.
  - `dot_config <key>` → prints the value for `key` from `$XDG_CONFIG_HOME/dotfiles/config` (empty string if file/key absent). Exit 0.
  - `dot_set_config <key> <value>` → upserts `key=value` (replaces an existing `key=` line in place, preserving other lines; appends if absent). Returns 0.

- [ ] **Step 1: Write the failing tests**

Create `tests/profile_helpers.bats`:

```bash
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export TERM=dumb
  source "$REPO/bin/lib/common.sh"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "dot_profile defaults to personal when unset" {
  run dot_profile
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "dot_set_profile then dot_profile round-trips work" {
  dot_set_profile work
  run dot_profile
  [ "$output" = "work" ]
}

@test "dot_set_profile rejects an invalid profile" {
  run dot_set_profile staging
  [ "$status" -ne 0 ]
}

@test "dot_profile falls back to personal on a garbage file" {
  mkdir -p "$XDG_CONFIG_HOME/dotfiles"
  printf 'garbage\n' >"$XDG_CONFIG_HOME/dotfiles/profile"
  run dot_profile
  [ "$output" = "personal" ]
}

@test "dot_config returns empty for an unset key" {
  run dot_config work_dir
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "dot_set_config then dot_config round-trips a value" {
  dot_set_config work_dir "$HOME/work"
  run dot_config work_dir
  [ "$output" = "$HOME/work" ]
}

@test "dot_set_config updates an existing key without duplicating it" {
  dot_set_config docker_runtime docker-desktop
  dot_set_config docker_runtime rancher
  run dot_config docker_runtime
  [ "$output" = "rancher" ]
  run grep -c '^docker_runtime=' "$XDG_CONFIG_HOME/dotfiles/config"
  [ "$output" = "1" ]
}

@test "dot_set_config preserves other keys" {
  dot_set_config work_dir "$HOME/work"
  dot_set_config docker_runtime rancher
  run dot_config work_dir
  [ "$output" = "$HOME/work" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/profile_helpers.bats`
Expected: failures — the helper functions are not defined yet (e.g. `command not found: dot_profile` / non-zero statuses).

- [ ] **Step 3: Implement the helpers in `common.sh`**

In `bin/lib/common.sh`, the last line is the `setup_colors` call. Insert this section immediately BEFORE that final `setup_colors` line:

```bash
########################################################
# Profile / machine config
########################################################
# State lives under $XDG_CONFIG_HOME/dotfiles/ — never committed.
# profile: a single word (personal|work). config: key=value lines.

_dot_state_dir() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"; }

# Print the active profile, defaulting to personal when unset/invalid.
dot_profile() {
  local file p="personal"
  file="$(_dot_state_dir)/profile"
  if [[ -f "$file" ]]; then
    p="$(tr -d '[:space:]' <"$file")"
  fi
  [[ "$p" == "personal" || "$p" == "work" ]] || p="personal"
  printf '%s\n' "$p"
}

# Persist the active profile. Rejects anything but personal|work.
dot_set_profile() {
  local name="${1:-}" dir
  if [[ "$name" != "personal" && "$name" != "work" ]]; then
    log_error "Invalid profile: '$name' (must be 'personal' or 'work')"
    return 1
  fi
  dir="$(_dot_state_dir)"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  printf '%s\n' "$name" >"$dir/profile"
}

# Print the value for a config key (empty if the file or key is absent).
dot_config() {
  local key="${1:-}" file line value=""
  file="$(_dot_state_dir)/config"
  [[ -f "$file" ]] || {
    printf '\n'
    return 0
  }
  while IFS= read -r line; do
    [[ "$line" == "$key="* ]] && value="${line#*=}"
  done <"$file"
  printf '%s\n' "$value"
}

# Upsert key=value: replace the existing key= line in place, else append.
dot_set_config() {
  local key="${1:-}" value="${2:-}" dir file tmp line found=0
  dir="$(_dot_state_dir)"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  file="$dir/config"
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == "$key="* ]]; then
        printf '%s=%s\n' "$key" "$value"
        found=1
      else
        printf '%s\n' "$line"
      fi
    done <"$file"
  fi >"$tmp"
  [[ "$found" -eq 0 ]] && printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv "$tmp" "$file"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/profile_helpers.bats`
Expected: `8 tests, 0 failures`.

- [ ] **Step 5: Run the full gate**

Run: `bin/dot test`
Expected: `All checks passed` (shellcheck/shfmt now also cover the new `common.sh` section).
If `shfmt` flags `common.sh`, run `shfmt -i 2 -ci -w bin/lib/common.sh` and re-run.

- [ ] **Step 6: Commit**

```bash
git add bin/lib/common.sh tests/profile_helpers.bats
git commit -m "feat(profile): add profile and config helpers to common.sh"
```

---

## Task 2: `dot profile` command + README

A thin CLI over the Task 1 helpers, auto-discovered by `bin/dot` (no change to `bin/dot` needed) and auto-gated by the Plan 1 lint surface.

**Files:**
- Create: `tests/dot_profile.bats`
- Create: `bin/dot-profile`
- Modify: `README.md`

**Interfaces:**
- Consumes: `dot_profile` / `dot_set_profile` / `dot_config` / `dot_set_config` from `common.sh` (Task 1).
- Produces: `dot profile get|set <name>|set-config <key> <value>|show|--help`. `get` prints the profile (script-friendly). `set`/`set-config` persist and `log_success`. `show` prints the profile + all config lines. Unknown subcommand or invalid input → non-zero exit.

- [ ] **Step 1: Write the failing tests**

Create `tests/dot_profile.bats`:

```bash
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export DOTFILES="$REPO"
  export TERM=dumb
  DOT_PROFILE="$REPO/bin/dot-profile"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

@test "get defaults to personal" {
  run "$DOT_PROFILE" get
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "set work then get returns work" {
  "$DOT_PROFILE" set work
  run "$DOT_PROFILE" get
  [ "$output" = "work" ]
}

@test "set rejects an invalid profile" {
  run "$DOT_PROFILE" set bogus
  [ "$status" -ne 0 ]
}

@test "set-config and show surface the value" {
  "$DOT_PROFILE" set work
  "$DOT_PROFILE" set-config work_dir "$HOME/work"
  run "$DOT_PROFILE" show
  [ "$status" -eq 0 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"work_dir"* ]]
}

@test "set-config requires both key and value" {
  run "$DOT_PROFILE" set-config work_dir
  [ "$status" -ne 0 ]
}

@test "--help exits 0" {
  run "$DOT_PROFILE" --help
  [ "$status" -eq 0 ]
}

@test "unknown subcommand exits non-zero" {
  run "$DOT_PROFILE" frobnicate
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/dot_profile.bats`
Expected: failures — `bin/dot-profile` does not exist yet (non-zero statuses / no such file).

- [ ] **Step 3: Create `bin/dot-profile`**

Create `bin/dot-profile` (made executable in Step 4):

```bash
#!/usr/bin/env bash
# Description: Manage the machine profile (personal|work) and per-machine config
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
DOTFILES="${DOTFILES:-$(cd "$script_dir/.." && pwd -P)}"
source "$DOTFILES/bin/lib/common.sh"

usage() {
  cat <<EOF
  $(fmt_key "Usage:") $(fmt_cmd "dot profile") $(fmt_value "<subcommand>")

Manage the machine profile and per-machine config.

$(fmt_key "Subcommands:")
    get                       Print the active profile (personal|work)
    set <personal|work>       Set the active profile
    set-config <key> <value>  Set a per-machine config value (e.g. work_dir, docker_runtime)
    show                      Show the profile and all config values
    -h, --help                Show this help
EOF
}

cmd_show() {
  printf "%b %s\n" "$(fmt_key 'profile:')" "$(dot_profile)"
  local file line
  file="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/config"
  if [[ -f "$file" ]]; then
    printf "%b\n" "$(fmt_key 'config:')"
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf "  %s\n" "$line"
    done <"$file"
  else
    printf "%b (none)\n" "$(fmt_key 'config:')"
  fi
}

main() {
  local sub="${1:-show}"
  shift || true
  case "$sub" in
    get) dot_profile ;;
    set)
      [[ $# -ge 1 ]] || {
        log_error "Usage: dot profile set <personal|work>"
        return 1
      }
      dot_set_profile "$1" && log_success "Profile set to $1"
      ;;
    set-config)
      [[ $# -ge 2 ]] || {
        log_error "Usage: dot profile set-config <key> <value>"
        return 1
      }
      dot_set_config "$1" "$2" && log_success "Set $1=$2"
      ;;
    show) cmd_show ;;
    -h | --help) usage ;;
    *)
      log_error "Unknown subcommand: $sub"
      usage
      return 1
      ;;
  esac
}

main "$@"
```

- [ ] **Step 4: Make it executable and verify the tests pass**

Run: `chmod +x bin/dot-profile && bats tests/dot_profile.bats`
Expected: `7 tests, 0 failures`.

- [ ] **Step 5: Document `dot profile` in the README**

In `README.md`, find the commands/usage section that lists the `dot` subcommands (near the `dot doctor` / `dot update` entries). Add a `dot profile` entry consistent with the existing style, for example:

```markdown
- `dot profile show` — show the active profile (personal|work) and per-machine config
- `dot profile set work` — switch the machine profile
- `dot profile set-config work_dir ~/work` — set a per-machine value (e.g. `work_dir`, `docker_runtime`)
```

If the README has no such list, add a short "Profile" subsection near the other `dot` command docs. Match the file's existing heading style and formatting.

- [ ] **Step 6: Run the full gate**

Run: `bin/dot test`
Expected: `All checks passed` — `bin/dot-profile` is auto-included in the lint set (`bin/dot-*` glob) and the two new bats files run. If `shfmt` flags `bin/dot-profile`, run `shfmt -i 2 -ci -w bin/dot-profile` and re-run.

Run: `pre-commit run --all-files`
Expected: all hooks Passed/Skipped.

- [ ] **Step 7: Commit**

```bash
git add bin/dot-profile tests/dot_profile.bats README.md
git commit -m "feat(profile): add dot profile command"
```

---

## Done criteria for Plan 2

- `dot profile show` reports `personal` on a machine with no profile file; `dot profile set work` then `dot profile get` returns `work`.
- `dot profile set-config work_dir ~/work` and `docker_runtime rancher` persist to `$XDG_CONFIG_HOME/dotfiles/config` and survive `dot profile show`.
- The four helpers are unit-covered (8 tests) and the CLI is covered (7 tests); `bin/dot test` and CI stay green.
- No `setup.sh`, Brewfile, or `dot doctor` changes — the spine is in place for Plans 3–4 to consume; nothing breaks when the profile file is absent (defaults to `personal`).
