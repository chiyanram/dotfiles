# `dot reconcile` gets a third resolution: `--ignore`, alongside `--adopt`/`--prune`

`dot reconcile <domain>` reports installed-but-undeclared items and resolves them
two ways: `--adopt` declares an item permanently in the shared Brewfile/toolchain/
`.zshrc` (committed, applies to every machine on that profile), or `--prune`
uninstalls it. There was no way to say "yes, I know this is installed on this
machine, leave it alone" — so a genuinely one-off/ad-hoc tool (installed for a
single client task, a one-time experiment) kept resurfacing in every report
forever, with adopt-it-for-real or uninstall-it as the only exits. In practice
this pushed toward `--adopt --all`, which declares every currently-undeclared
item in one shot with no per-item review — see #95, where that's exactly how
seven undescribed placeholder entries ended up committed.

Decided: add `--ignore`/`--unignore`, a third, deliberately **machine-local and
reversible** resolution — the opposite end of the spectrum from `--adopt`
(shared, permanent, requires a real description) and a softer version of
`--prune` (destructive, uninstalls). State lives in
`~/.config/dotfiles/reconcile-ignore`, never committed, same convention as
`~/.config/dotfiles/profile` — "which one-offs I don't want to declare" is
inherently per-machine, not shared dotfiles state. Ignored items are excluded
from `undeclared` (so `--adopt --all` can never re-sweep them) and shown in a
dim "ignored (informational)" report section so they don't vanish from view
entirely.
