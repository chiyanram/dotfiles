---
name: brewfile-add
description: Add a new Homebrew formula or cask to this repo's brew/Brewfile.* files, following the four documented rules (category placement, macOS cask guard, no deprecated taps, trailing comment). Use when the user wants to add a brew/cask package to the dotfiles.
---

# Add a Brewfile Entry

CLAUDE.md's Brewfile rules, applied every time:

1. **Pick the right file.**
   - `brew/Brewfile.core` — cross-profile (installed on every machine)
   - `brew/Brewfile.personal` / `brew/Brewfile.work` — profile-specific (selected by `dot profile get`)

2. **Place it under the right category comment** (macOS, core, shell, dev tools, infra — see the existing `# Section` comments in the target file). Don't invent a new top-level section unless nothing fits.

3. **Casks go inside `if OS.mac?`.** `brew/Brewfile.core` already has a top-level `if OS.mac? ... elsif OS.linux? ... end` block for cross-platform entries — add cask lines inside the `OS.mac?` branch. A macOS-only formula follows the same rule; a cross-platform formula goes outside the conditional.

4. **No deprecated taps.** `homebrew/bundle` is built into Homebrew now — never add a `tap` line for it. Check whether the package needs a tap at all before adding one.

5. **Every entry gets a trailing comment** explaining what the tool is, aligned with the existing entries' comment column in that file (`brew 'name'<spaces># description`).

## After adding

- Validate formatting/lint: `pre-commit run --all-files` (or at minimum `shfmt`/`shellcheck` don't apply here, but `prettier`/`check-yaml` may touch adjacent files — pre-commit is the safe check for a Brewfile-only change).
- Optionally install to verify: `dot homebrew bundle`.
- This is a config change, not a script/test change — still follows the repo's issue+branch+worktree ritual unless bundled into a larger change that already has one.
