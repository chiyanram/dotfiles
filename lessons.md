# Lessons Learned

Rules derived from mistakes. Review before making changes.

## ZSH Config

### Never remove code without tracing all callers
**Mistake:** Removed `compinit` from `.zsh_functions` because a reviewer flagged it as "duplicate". Didn't check that `compdef` calls on lines 14/23 depend on it. `.zsh_functions` is sourced BEFORE `.zshrc`'s compinit.
**Rule:** Before removing any line, grep for everything it provides. `compinit` provides `compdef`, `compadd`, etc. — search for all of them.

### Never alias POSIX core commands
**Mistake:** Aliased `find` to `fd`. SDKMAN's init script uses `find` internally with GNU syntax. `fd` couldn't parse it, so all SDKMAN functions were never defined — causing 20+ "command not found" errors.
**Rule:** Never alias `find`, `grep`, `sed`, `awk`, `sort`, `cat` (bat is OK since bat handles cat args), `ls`, `rm`, `cp`, `mv`. Other tools call these internally. Use distinct names (`fd` is already its own command).

### macOS ships BSD tools, not GNU
**Mistake:** Used `readlink -f` which is GNU coreutils. macOS has BSD `readlink` which doesn't support `-f`. Fails silently — returns empty string.
**Rule:** For ZSH scripts, use ZSH builtins (`:A` modifier for realpath). For bash scripts, use `cd && pwd -P` pattern. Never assume GNU coreutils on macOS.

### Always test shell changes in a real interactive shell
**Mistake:** Made 15 changes to `.zshrc`, `.zsh_functions`, `.zsh_aliases` in one commit without testing `zsh -i -c 'echo ok'`. All three bugs would have been caught.
**Rule:** After any `.zshrc`/`.zsh_functions`/`.zsh_aliases` change, run `zsh -i -c 'echo ok' 2>&1` and check for errors before committing.

### ZSH plugin load order matters
**Mistake:** Put `history-substring-search` keybindings in the Key Bindings section, before the plugin was loaded in the Plugin Management section. Widgets didn't exist yet.
**Rule:** Keybindings for plugin-provided widgets must come AFTER the plugin is loaded. Keep them adjacent to the `zfetch` call.

### fzf-git.sh is not a standard ZSH plugin
**Mistake:** Loaded `fzf-git.sh` via `zfetch` like other plugins. It registers `zle` widgets at source time, which fails in non-interactive shells.
**Rule:** Scripts that use `zle` must be guarded with `[[ -o zle ]]`. `fzf-git.sh` needs manual sourcing with this guard, not standard `zfetch`.

## Homebrew / Brewfile

### HOMEBREW_ prefix required for Brewfile env vars
**Mistake:** Used `DOCKER_RUNTIME` env var in Brewfile's `ENV.fetch()`. Homebrew sanitizes the environment and strips non-`HOMEBREW_*` prefixed vars.
**Rule:** All env vars intended for Brewfile must use `HOMEBREW_` prefix.

## Bash Scripts

### trap EXIT overwrites are destructive
**Mistake:** Every function in `dot-update` set `trap 'rm -f ...' EXIT`, overwriting `bin/dot`'s cursor-restore trap. When a function failed, the terminal was left broken.
**Rule:** Never use `trap EXIT` inside functions. Use explicit cleanup (`rm -f`) instead.

### exit vs return in functions under set -e
**Mistake:** Used `exit 1` inside functions in `dot-update`. Under `set -e`, this kills the entire script, not just the function.
**Rule:** Use `return 1` in functions, `exit 1` only in `main()`.

### git config returns exit 1 for missing keys
**Mistake:** `dot-git` used `defaultName=$(git config user.name)` without error handling. On a fresh machine, this exits 1 and kills the script under `set -Eeuo pipefail`.
**Rule:** Always use `$(git config ... 2>/dev/null || true)` when the key might not exist.

## General

### Fresh machine != configured machine
**Mistake:** Multiple scripts assumed tools were already installed, env vars were set, symlinks existed. None of this is true on a fresh laptop.
**Rule:** Every script must work on day 0. Guard every tool check with `command -v`. Guard every file check with `[[ -f ... ]]`. Guard every dir check with `[[ -d ... ]]`.
