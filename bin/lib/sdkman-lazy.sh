# shellcheck shell=bash
# Pure, sourceable helpers for SDKMAN lazy-loading.
# Sourced by both home/.zshrc (zsh) and tests/sdkman_lazy.bats (bash) — keep it
# POSIX-portable: no zsh glob qualifiers, no bashisms beyond what zsh also accepts.

# Print each candidates/<tool>/current/bin directory under <sdkman_dir>, one per
# line. Prints nothing if the dir is absent or no candidate has a current/bin.
# Pure: same input -> same output, no side effects.
_sdkman_candidate_bins() {
  local dir="${1:-}" bin
  [[ -d "$dir/candidates" ]] || return 0
  for bin in "$dir"/candidates/*/current/bin; do
    [[ -d "$bin" ]] && printf '%s\n' "$bin"
  done
  return 0
}

# Return 0 iff a .sdkmanrc exists in the current working directory. Pure
# predicate (reads the filesystem, writes nothing).
_sdkman_has_rc() {
  [[ -f .sdkmanrc ]]
}
