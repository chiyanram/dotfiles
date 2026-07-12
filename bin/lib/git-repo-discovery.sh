#!/usr/bin/env bash
# Repo discovery for the identity-slot system — the conventional roots to scan
# and the repos found under them. Shared by BOTH `dot doctor`'s identity audit
# and `dot git migrate` so the proactive sweep and the interactive onboarding
# walk the exact same repos.
#
# Read-only (find/read), but depends on bin/lib/profile.sh's `dot_config` for
# the `git_audit_roots` override — self-sourced below, so callers don't need
# to know that. bash-3.2-safe (no assoc arrays / mapfile).

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

# Print the roots to scan, one per line: the hardcoded conventional set plus any
# `git_audit_roots` override (whitespace/newline-separated), which AUGMENTS the
# defaults rather than replacing them — a missed default is never silently lost.
git_slot_audit_roots() {
  local r override
  for r in work workspace dev dotfiles personal clients; do
    printf '%s\n' "$HOME/$r"
  done
  override="$(dot_config git_audit_roots)"
  [[ -n "$override" ]] && printf '%s\n' "$override" | tr '[:space:]' '\n'
}

# Print the `.git` directory of every repo under the existing roots (absent roots
# are skipped silently). maxdepth 3 covers root/.git, root/repo/.git and one org
# level (root/org/repo/.git); -prune stops the descent into a found repo.
git_slot_audit_dirs() {
  local root
  while IFS= read -r root; do
    [[ -n "$root" && -d "$root" ]] || continue
    find "$root" -maxdepth 3 -type d -name .git -prune 2>/dev/null
  done < <(git_slot_audit_roots) | sort -u
}
