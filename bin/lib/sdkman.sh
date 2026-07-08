#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

########################################################
# SDKMAN
########################################################
# run_sdk <args...> — run `sdk <args...>` in a PATH-bash subprocess, TTY attached.
# Never `source` sdkman-init.sh into a dot script's own process: the init script
# expands unset vars (a `set -u` abort that escapes the step runner's `||` catch
# and kills the whole script) and uses bash-4-only syntax (${var^^}). The PATH
# bash must be >= 4 (Homebrew's), which the callers ensure before invoking.
run_sdk() {
  # stdin from /dev/null so an `sdk install` "set as default? (Y/n)" prompt can't
  # block an unattended run — it reads EOF and proceeds; callers that care about
  # the default set it explicitly with `sdk default`.
  bash -c 'source "${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh" && sdk "$@"' sdk "$@" </dev/null
}
