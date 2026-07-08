---
name: doctor-triage
description: Interpret a `dot doctor` report and propose the specific fix for each failing section (Profile, Config Links, Shell, Homebrew Packages, Java/Backend, SSH, Git Identity, Drift). Use when the user runs dot doctor and wants help understanding or fixing what it flagged.
---

# Triage a `dot doctor` Report

`dot doctor` (`bin/dot-doctor`) checks unrelated tool categories in one pass, each under its own `fmt_title_underline` section. Don't propose one generic fix — map each finding to its section and the specific command that addresses it.

## Run it

```
dot doctor        # normal run
dot doctor --strict   # treat warnings as failures too
```

## Section → likely cause → fix

- **Profile** — wrong/unset machine profile. Fix: `dot profile set <personal|work>`.
- **Config Links** / a stale or dangling symlink — a `config/*` or `home/*` target drifted from what `dot link` expects. Fix: `dot link all -v` to relink, or `dot link --status` to see per-target state first. A dangling link whose source was deleted: `dot clean`.
- **Shell** — wrong default shell or a zsh plugin didn't load. Fix: `chsh -s $(which zsh)` for the shell; re-run `dot-update` or check `.zsh_functions`'s `zfetch` calls for the plugin.
- **Homebrew Packages** — a declared Brewfile formula/cask is missing, or an installed one isn't declared (drift). Fix missing: `dot homebrew bundle`. Fix undeclared drift: either add it to the right `brew/Brewfile.*` (see `brewfile-add` skill) or remove it if unintended.
- **Java / Backend** (SDKMAN candidates) — a candidate is missing or installed but not on PATH. Fix: `sdk install <candidate>` via the SDKMAN shell, or check `.sdkmanrc`/`home/.zshrc`'s lazy-load section if it's on-disk but not resolving.
- **SSH** — GitHub SSH auth isn't working for a host alias. Fix: check `~/.ssh/config` has the identity-slot alias, `ssh-add -l` shows the key loaded, and the key is registered on GitHub.
- **Git Identity** — a repo under a conventional root (`~/work`, `~/dotfiles`, etc.) has no matching identity slot, or its `gh` account doesn't match the slot's. Fix: `dot git add-identity` (new slot) then `dot git use <slot>` (bind repo), or `dot git migrate` to walk every flagged repo interactively. A gh-drift warning specifically: `gh auth switch` to the slot's account, or re-run `dot git use <slot>` which syncs both.
- **Drift** (from `dot reconcile`) — installed-but-undeclared or declared-but-missing state across Homebrew/SDKMAN/symlinks in one summary. Fix per the specific line it prints, using the mappings above.

## After fixing

Re-run `dot doctor` (or `dot doctor --strict` if that's what surfaced the issue) and confirm the section is clean before considering the fix done — a claimed fix without a clean re-run is a guess, not a verified result, per this repo's "don't call it done until it's green" rule.
