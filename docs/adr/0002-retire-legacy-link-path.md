# Retire the legacy link/unlink path via a symmetric apply pair

## Context

Three generations of link/unlink logic coexisted in `bin/dot`: `link_apply` +
`link_plan` over `managed_targets`/`classify_link` (the deep path, used only by
`link all`, with manifest recording so `dot restore` can undo it); `link_home_files`
(home walk, link+unlink modes) and `link_config` (per-package), a legacy generation
used by `unlink all` and single-package `link <pkg>`/`unlink <pkg>`, with its own
copy of classify-and-act logic and no manifest recording; and `cmd_link`'s inline
unlink loops, a third copy of the same `-L`/`rm`/warn logic. The legacy unlink path
never checked whether a symlink actually pointed into `$DOTFILES` before removing
it — a real foreign-symlink deletion risk, and unlike `link all`, nothing about it
was undoable via `dot restore`.

## Decision

- A new sibling function `unlink_apply(source, target, label, verbose)` handles
  the unlink direction, separate from `link_apply` rather than a mode flag on it.
  Its signature is deliberately narrower — no `force`/`backup`/`adopt`, none of
  which mean anything when unlinking. It shares `classify_link` as the only piece
  in common with `link_apply`.
- Unlink acts on the same four `classify_link` states, with unlink-specific
  behavior: `missing` → nothing to do; `ok` (points exactly at our source) →
  remove it and `manifest_record "delete" "$target" "$source"`; `wrong` (points
  anywhere else) → refuse and warn, no override — this covers both a truly
  foreign symlink and a stale-but-ours one left behind by a renamed package,
  treated identically; `real` → refuse and warn (unchanged from today).
- `cmd_restore` gains a fourth manifest action, `delete`: `ln -s "$prev" "$target"`
  if `[ ! -e "$target" ]`, recreating the symlink `unlink_apply` removed. The
  guard mirrors the existing pattern on `replace`/`backup` (never clobber
  something that now occupies the path).
- Manifest-tracking extends to single-package `link <pkg>` / `unlink <pkg>`, not
  just `all` — today single-package `link` is silently un-undoable, since
  `DOT_MANIFEST` is only ever set up for the `all` branch. Each single-package
  call wraps its one `link_apply`/`unlink_apply` call in its own scoped
  `DOT_MANIFEST`.
- Single-package still constructs its own `source`/`target` pair directly in the
  caller (`$DOTFILES/config/$pkg` / `$CONFIG_HOME/$pkg`), the same as today,
  rather than growing `managed_targets` with a package-name filter.

## Considered options

- **A mode flag on `link_apply`** instead of a sibling function — rejected: every
  `case` arm would need an `if mode==link/else` split, and `force`/`backup`/
  `adopt` would be threaded through unlink calls where none of them apply.
- **A path-prefix "does this point into `$DOTFILES`" check** instead of reusing
  `classify_link`'s exact-match `wrong` state — rejected: new path-normalization
  logic for a rare case (a stale link after a package rename) that's already
  handled safely by a warning; the exact-match reuse is zero new code and stays
  consistent with the sibling-function decision.
- **Defer single-package manifest-tracking to a follow-up** — rejected: it's a
  natural byproduct of building `unlink_apply`, and single-package `link` being
  silently un-undoable is a real, pre-existing gap worth closing now rather than
  filing yet another issue for it.
- **Growing `managed_targets` with a package-name filter** — rejected: it would
  force a bulk-oriented enumerator (which silently skips empty packages) to also
  carry single-package-only warn-on-empty semantics, conflating two callers'
  needs. Single-package already constructs its own pair today; this is a strict
  subset of current behavior, not a new pattern. Per YAGNI, revisit only if a
  second consumer needs a filtered lookup.

## Consequences

- `cmd_link`'s inline unlink loops and `link_home_files`'s unlink mode are
  deleted, replaced by calls to `unlink_apply`.
- Every link/unlink path — `all` or single-package — now goes through an apply
  function backed by `classify_link` and a manifest, so `dot restore` can undo
  any of them.
- A stale link into `$DOTFILES` left behind by a renamed package will refuse to
  unlink automatically; the fix is a one-time manual `rm`, surfaced by name in
  the warning.
- Slices 1-3 of this series landed as #43/#45/#47; this is slice 4 (issue #48).
  #49 (split `common.sh`) and #50 (source-guard + bats for bare-`main` scripts)
  are next, per the umbrella issue #52's fixed order.
