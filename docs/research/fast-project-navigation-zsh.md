# Fast project navigation in zsh

> **Where this lives & why:** saved at `docs/research/fast-project-navigation-zsh.md`.
> The repo already keeps docs under `docs/adr/` (decision records) and `docs/agents/`,
> but has **no existing convention for research/notes**. Rather than overload `adr/`
> (these are options, not a decision) I created a new `docs/research/` folder for
> primary-source research notes like this one.
>
> **Scope:** research only. This note does **not** edit `home/.zshrc`,
> `home/.zsh_functions`, or `home/.zsh_aliases` — every snippet below is
> copy-paste-ready and says which file to paste it into.
>
> Verified on this machine (2026-07-15): zsh 5.9.2, zoxide 0.10.0, fzf 0.74.0,
> fd 10.4.2 — all on PATH via Homebrew.

---

## How this was applied (issue #163)

To keep machine-specific paths out of the shared dotfiles, the mechanisms below
were split between committed and machine-local config:

- **Committed** (`home/.zshrc`, generic): `CODE_DIR` made overridable
  (`export CODE_DIR="${CODE_DIR:-$HOME/Workspaces}"`), `cdpath=("$CODE_DIR" "$HOME")`,
  and fzf `Alt-C` scoping via `FZF_ALT_C_COMMAND`/`FZF_ALT_C_OPTS`.
- **Machine-local** (not committed): `export CODE_DIR=$HOME/workspace` in
  `~/.zshenv.local` (sourced by `.zshenv` before `.zshrc`, so `cdpath` picks it up),
  and `hash -d ap=… / n8n=…` in `~/.zshrc.local`.
- **No change:** `z`/`zi` (zoxide) already work; `c()`/`_c` start working once the
  local `CODE_DIR` is correct.

The mechanism sections below describe each option generically; the file/line
suggestions in them predate the committed-vs-local split above.

## Bottom line

You already have **more navigation power installed than you're using**, and one
real bug is likely why you keep falling back to `ls -lrt`.

1. **Fix the broken `CODE_DIR` first (this is a bug, not an enhancement).**
   `home/.zshrc:65` sets `export CODE_DIR=~/Workspaces`, but that directory does
   **not exist** — your projects are in `~/workspace` (lowercase): `~/workspace/agent-platform`,
   `~/workspace/n8n`. So your custom `c()` function (`cd $CODE_DIR/$1`, `home/.zsh_functions:5`)
   and its `_c` completion are pointed at a non-existent path and silently fail.
   Change one line to `export CODE_DIR=~/workspace` and `c agent-platform` /
   `c <Tab>` start working again.

2. **You already have `z` (zoxide) — just use it.** Your zoxide database already
   contains `~/workspace/agent-platform` and `~/workspace/n8n`. `z n8n` jumps
   straight there today; `z agent<Tab>` completes it. No config change needed —
   this alone replaces the `ls -lrt` hunting for dirs you've visited before.

3. **Add `cdpath` (one line).** You already have `setopt AUTO_CD` (`home/.zshrc:76`),
   so `cd` isn't even required. Adding `cdpath=($CODE_DIR)` makes
   `agent-platform` + Enter cd into `~/workspace/agent-platform` **from anywhere**,
   with native Tab completion — no custom function, works for dirs you've never visited.

4. **Add two `hash -d` named dirs** for the projects you live in, so `~ap` / `~n8n`
   expand everywhere (in `cd`, in any command, in editor args) and your prompt
   shows `~ap` instead of the long path.

5. **Scope fzf's Alt-C to your projects** (optional). Alt-C is already bound
   (`fzf-cd-widget`), but it searches from the current dir. Point
   `FZF_ALT_C_COMMAND` at `$CODE_DIR` so Alt-C always fuzzy-picks a project.

Smallest win: do **1 + 2**. Then **3 + 4** are two lines each. **5** is polish.

---

## The mechanisms

### 0. The bug: `CODE_DIR` points at a directory that doesn't exist

Verified on this machine:

```
$ ls -ld ~/Workspaces
ls: /Users/chiyanram/Workspaces: No such file or directory
$ ls -1 ~/workspace
agent-platform
n8n
```

**Fix — edit `home/.zshrc:65`:**

```zsh
# was: export CODE_DIR=~/Workspaces
export CODE_DIR=~/workspace
```

Everything below assumes `CODE_DIR=~/workspace`. Your existing `c()` /`_c` and
`h()`/`_h` helpers (`home/.zsh_functions:5-19`) become useful again after this.

---

### 1. zoxide — `z` and `zi` (already installed & configured)

Initialized at `home/.zshrc:178-180` via `eval "$(zoxide init zsh)"`.

**What it gives you** (primary source: <https://github.com/ajeetdsouza/zoxide>):

- `z foo` — "cd into highest ranked directory matching foo."
- `z foo bar` — "cd into highest ranked directory matching foo and bar."
- `zi foo` — "cd with interactive selection (using fzf)" (the `zi` picker shells out
  to your installed fzf).
- `z foo<SPACE><TAB>` — "interactive completions (bash 4.4+/fish/zsh only)."
  Verified: zoxide 0.10.0's `zoxide init zsh` defines `__zoxide_z_complete` and
  registers it with `compdef`, so **`z agent<Tab>` completion already works** for you.

**How `z foo` matches** (primary source, the frecency/matching wiki:
<https://github.com/ajeetdsouza/zoxide/wiki/Algorithm>):

- Case-insensitive: `z foo` matches `/foo` and `/FOO`.
- Sequential: "All terms must be present (including slashes) within the path, in order."
  So `z fo ba` matches `/foo/bar` but not `/bar/foo`.
- Final-component constraint: "The last component of the last keyword must match the
  last component of the path." So `z bar` matches `/foo/bar` but not `/bar/foo`.
- "Matches are returned in descending order of frecency."

**Frecency scoring** (same wiki): each dir starts at score 1 and +1 per visit; the
score is then weighted by recency — `× 4` within the last hour, `× 2` within the last
day, `÷ 2` within the last week, `÷ 4` if older.

**Requires the hook** (which you have): zoxide only knows a directory after you've
`cd`'d there while its shell hook is active — the `init` line installs a `pwd` hook
that records every directory change (<https://github.com/ajeetdsouza/zoxide>).

**Are you under-using it? Yes.** Your DB already has the two projects. Verified:

```
$ zoxide query n8n
/Users/chiyanram/workspace/n8n
$ zoxide query -l | head
/Users/chiyanram/workspace/agent-platform
/Users/chiyanram/workspace
/Users/chiyanram/workspace/n8n
...
```

So `z n8n` and `z agent-platform` (or `z agent<Tab>`) already solve the "jump to a
project I use often" case with **zero new config** — this is the single biggest lever.

**vs. your `c()`:** `c` needs the project to be a direct child of `$CODE_DIR` and
requires you to know/type the name; `z` matches on frecency across *any* path you've
visited (including nested dirs like `.../agent-platform/aruvii-ui`, already in your DB)
and tolerates partial queries. `c` is deterministic (good for scripting/muscle memory);
`z` is fuzzy and history-driven. They complement each other.

---

### 2. zsh `cdpath` — make `agent-platform` work from anywhere

Primary source, zsh manual, Parameters (<https://zsh.sourceforge.io/Doc/Release/Parameters.html>):

> "An array (colon-separated list) of directories specifying the search path for the
> `cd` command."

With `cdpath=($CODE_DIR)`, typing `cd agent-platform` from *any* directory searches
`~/workspace/agent-platform` and cd's there. Because you already have
`setopt AUTO_CD` (`home/.zshrc:76`) — zsh manual, Options
(<https://zsh.sourceforge.io/Doc/Release/Options.html>):

> "If a command is issued that can't be executed as a normal command, and the command
> is the name of a directory, perform the `cd` command to that directory."

— you can even drop the `cd` and just type `agent-platform` + Enter. And zsh's
completion honours `cdpath`, so `cd agent<Tab>` completes project names.

**Add to `home/.zshrc`** (right after `CODE_DIR` is set, ~line 65):

```zsh
# Let `cd <name>` (and bare `<name>` via AUTO_CD) resolve project dirs from anywhere.
cdpath=("$CODE_DIR" "$HOME")
```

One caveat worth knowing: with `cdpath` set, a bare name that also exists as a
subdir of the current dir still prefers the local one first, then falls back to
`cdpath` — so it won't surprise you inside a project.

**vs. your `c()`:** `cdpath` covers the same "jump to a child of `$CODE_DIR`" case but
with the native `cd`/bare-word syntax and native completion, and it does **not** shadow
the current directory. `c` is a fine explicit alias to keep; `cdpath` just means you no
longer *need* it.

---

### 3. zsh named directories — `hash -d` for `~ap`, `~n8n`

Primary source, zsh manual, Filename Expansion / Static named directories
(<https://zsh.sourceforge.io/Doc/Release/Expansion.html>):

> "It is also possible to define directory names using the `-d` option to the `hash`
> builtin."

and the `hash` builtin, zsh manual, Shell Builtin Commands
(<https://zsh.sourceforge.io/Doc/Release/Shell-Builtin-Commands.html>):

> "For each name with a corresponding value, put `name` in the selected hash table …
> In the named directory hash table, this means that `value` may be referred to as
> `~name`."

So `hash -d ap=~/workspace/agent-platform` makes `~ap` expand to that path
**everywhere a path is accepted** — `cd ~ap`, `code ~ap`, `cat ~ap/README.md`, etc.
Bonus (same Expansion page): when the shell prints a path (e.g. `%~` in your prompt),
it abbreviates the prefix back to `~ap`, so **starship will show `~ap`** instead of the
full path.

**Add to `home/.zsh_functions`** (near the Navigation block, ~line 20; these are static
strings, no `$CODE_DIR` needed but you can use it):

```zsh
# Named directories: `cd ~ap`, `cat ~n8n/…`, and prompt shows ~ap / ~n8n.
hash -d ap="$CODE_DIR/agent-platform"
hash -d n8n="$CODE_DIR/n8n"
```

**vs. `z` / `cdpath`:** named dirs are the most "typed-path-anywhere" option — they work
in *any* command, not just `cd`, and they clean up your prompt. Downside: each is
hand-maintained (add a line per project), whereas `z` learns automatically and `cdpath`
covers all children at once. Best for the 2-3 repos you truly live in.

---

### 4. fzf Alt-C — scope the interactive dir-picker to your projects

Alt-C is already bound (your `source <(fzf --zsh)` at `home/.zshrc:192` installs
`fzf-cd-widget` on `\ec`; verified). Primary source, fzf README, key bindings
(<https://github.com/junegunn/fzf#key-bindings-for-command-line>):

> "ALT-C - cd into the selected directory"

By default Alt-C walks directories under the **current** dir. To make Alt-C always
fuzzy-pick a *project* regardless of where you are, override its source command with
`FZF_ALT_C_COMMAND` (README, environment variables) and optionally `FZF_ALT_C_OPTS`:

**Add to `home/.zshrc`** inside the existing FZF block (after line 191, before
`source <(fzf --zsh)` at line 192 so the vars are set first):

```zsh
# Alt-C fuzzy-picks a project dir under $CODE_DIR, from anywhere.
export FZF_ALT_C_COMMAND="fd --type d --max-depth 2 . \"$CODE_DIR\""
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=1 --icons --color=always {} 2>/dev/null | head -100'"
```

(You already have `fd` and `eza`, so both lines work as-is. Drop the `--preview` line
if you don't want it.)

Also available with no config — fuzzy completion, fzf README
(<https://github.com/junegunn/fzf#fuzzy-completion-for-bash-and-zsh>): the default
trigger is `**`, so **`cd ~/workspace/**<TAB>`** opens an fzf picker of matching dirs.
The trigger is configurable via `FZF_COMPLETION_TRIGGER`.

**vs. `zi`:** zoxide's `zi` picks from your *frecent* history (dirs you've visited);
scoped Alt-C / `**<Tab>` picks from the *filesystem* under `$CODE_DIR` (including brand-new
projects you've never cd'd into). Use `zi` for "somewhere I've been", Alt-C for "browse
what's there".

---

## Comparison

| Mechanism | Trigger | Matches | Needs prior visit? | New config | Best for |
|---|---|---|---|---|---|
| `z` (zoxide) — **have it** | `z n8n`, `z agent<Tab>` | frecency, fuzzy, any visited path | Yes (hook-tracked) | none | Jumping to projects you use often |
| `zi` (zoxide) — **have it** | `zi` | interactive fzf over frecent dirs | Yes | none | "I've been there, let me pick" |
| `cdpath` + AUTO_CD (have AUTO_CD) | `agent-platform`↵ or `cd a<Tab>` | children of `$CODE_DIR`, native completion | No | 1 line | Any project child, from anywhere |
| `hash -d` named dir | `cd ~ap`, `~ap` in any cmd | exact, path-anywhere; abbreviates prompt | No | 1 line/project | The 2-3 repos you live in |
| fzf Alt-C (bound; scope it) | `Alt-C` | fuzzy over dirs under `$CODE_DIR` | No | 2 lines | Browsing/fuzzy-finding a project |
| `**<Tab>` (fzf completion) | `cd $CODE_DIR/**<Tab>` | fuzzy filesystem | No | none | Ad-hoc fuzzy path completion |
| `c()` — **have it** (fix CODE_DIR) | `c agent-platform` | direct child of `$CODE_DIR` | No | fix bug §0 | Explicit muscle-memory alias |

---

## Recommended minimal diff (summary)

1. `home/.zshrc:65` — `export CODE_DIR=~/workspace` (fixes the broken path; **do this**).
2. `home/.zshrc` after line 65 — `cdpath=("$CODE_DIR" "$HOME")`.
3. `home/.zsh_functions` ~line 20 — two `hash -d ap=… / n8n=…` lines.
4. (optional) `home/.zshrc` in the FZF block — `FZF_ALT_C_COMMAND`/`FZF_ALT_C_OPTS`.
5. Nothing to install; nothing to change for `z`/`zi` — just start typing `z n8n`.

---

## Primary sources

- zoxide — README (commands `z`, `zi`, tab completion, tracking hook):
  <https://github.com/ajeetdsouza/zoxide>
- zoxide — Algorithm wiki (frecency scoring + `z foo` matching rules):
  <https://github.com/ajeetdsouza/zoxide/wiki/Algorithm>
- fzf — key bindings (ALT-C, CTRL-T, CTRL-R) & env vars (`FZF_ALT_C_COMMAND`,
  `FZF_ALT_C_OPTS`, `FZF_CTRL_T_COMMAND`, `FZF_DEFAULT_COMMAND`, `FZF_DEFAULT_OPTS`):
  <https://github.com/junegunn/fzf#key-bindings-for-command-line>
- fzf — fuzzy completion (`**<TAB>` trigger, `FZF_COMPLETION_TRIGGER`):
  <https://github.com/junegunn/fzf#fuzzy-completion-for-bash-and-zsh>
- zsh manual — Parameters (`cdpath`/`CDPATH`):
  <https://zsh.sourceforge.io/Doc/Release/Parameters.html>
- zsh manual — Options (`AUTO_CD`):
  <https://zsh.sourceforge.io/Doc/Release/Options.html>
- zsh manual — Filename Expansion / Static named directories (`~name`, `hash -d`):
  <https://zsh.sourceforge.io/Doc/Release/Expansion.html>
- zsh manual — Shell Builtin Commands (`hash -d name=value`):
  <https://zsh.sourceforge.io/Doc/Release/Shell-Builtin-Commands.html>
