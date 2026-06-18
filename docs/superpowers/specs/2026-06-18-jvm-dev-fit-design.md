# JVM Polyglot Dev Fit — Design Spec

**Date:** 2026-06-18
**Owner:** Chiyanram (senior backend engineer, codes ~8h/day — Java, Kotlin, Scala, Gradle, Maven, Testcontainers, Docker, IntelliJ; macOS Apple Silicon; work + personal laptops)
**Status:** Approved design, pending spec review → implementation plan

## 1. Goal

Make the shell + tooling fit the owner's real polyglot-JVM profile. The original audit assumed Java/Gradle; the actual stack is wider (Kotlin, Scala, Maven, Testcontainers). This closes the gaps the second look surfaced: a starship prompt that recognises all three JVM languages, Docker helpers that survive a Testcontainers-heavy workflow, per-project JDK auto-switching that already-present `.sdkmanrc` files expect, and three missing power tools.

## 2. Decisions locked during brainstorming

- **Docker scope = focused:** fix the existing bugs + add Testcontainers hygiene + a context switcher. Not a full `.docker_aliases` rewrite.
- **starship:** re-enable Kotlin, add Scala, and **remove `build.sbt` from the `[java]` module's `detect_files`** so a Scala/sbt project shows the Scala badge alone (not Java + Scala).
- **SDKMAN auto-env:** flip `sdkman_auto_env=true` reproducibly via a `setup.sh` step (the file is machine-local and cannot be symlinked) plus a `dot-doctor` check.
- **Tools:** add `ktlint`, `async-profiler`, `jdk-mission-control` — all to `brew/Brewfile.core`.
- **Git is out of scope** — the alias set + `gcom`/`grbm`/`gpum`/`gll` functions are already strong; nothing to change.

## 3. Non-goals (out of scope)

- A full `.docker_aliases` rewrite (commented-alias cleanup, lazydocker/dive shortcuts) — explicitly deferred.
- Any git change.
- Neovim, terminal-emulator, or atuin/sesh work (covered by other specs).
- Switching version managers (SDKMAN + fnm stay).
- Installing the `tenv`/`tflint` tap tools (separate; they need tap-trust).

## 4. Global constraints

- macOS only, Apple Silicon. Conventional Commits; **no `Co-Authored-By`**.
- `.docker_aliases` is sourced by zsh; keep it POSIX/bash-portable, BSD-safe (no GNU `sed -i`, no `readlink -f`). Never alias/shadow POSIX core commands.
- `bin/` scripts keep `set -Eeuo pipefail`, `return 1` (not `exit 1`) in functions, no `trap EXIT` in functions, and source `$DOTFILES/bin/lib/common.sh` (use `log_*` helpers). `setup.sh` edits to `~/.sdkman/etc/config` must be **idempotent** and guarded (`[[ -f ]]`).
- **Destructive Docker helpers must be label-scoped:** `tc-clean` only ever targets resources carrying the `org.testcontainers` label — it must never touch a non-Testcontainers container/volume/network.
- Work/personal: `dctx` reads/echoes the `docker_runtime` config key already used by the repo (`~/.config/dotfiles/config`); it does not hardcode one runtime.
- Validation gates: `starship` renders without error; `.docker_aliases` passes shellcheck and sources clean; `zsh -i -c 'echo ok'` is clean; `bin/dot test` + `pre-commit run --all-files` stay green.

## 5. Design

### A — starship polyglot fit (`config/starship/starship.toml`)
- **Kotlin:** remove `[kotlin] disabled = true`; style it (catppuccin macchiato, Nerd Font glyph); add `$kotlin` to the `format` string after `$java`.
- **Scala:** add a `[scala]` block (catppuccin style + glyph) and `$scala` to the format. It detects `build.sbt`, `.scala`, `.sc`, `.metals`.
- **Java/sbt disambiguation:** remove `build.sbt` from `[java].detect_files` (keep `pom.xml`, `build.gradle`, `build.gradle.kts`, `.java-version`). A Scala/sbt project then shows only the Scala badge; a Java/Maven/Gradle project shows only Java; a mixed Gradle-Kotlin project shows Java + Kotlin.
- Keep the existing always-on Kubernetes module, Terraform, and the disabled-noise modules untouched.

### B — Docker / Testcontainers (`home/.docker_aliases`)
- **Bug fixes** (behavior-preserving except for the dropped-arg fix):
  - `drun-fn`: `docker run -it "$1" "$2"` → `docker run -it "$@"`.
  - `d-aws-cli-fn`: `... amazon/aws-cli:latest "$1" "$2" "$3"` → `... amazon/aws-cli:latest "$@"`.
  - `dip-fn`: declare `local OUT` (it is currently a global mutated with `+=` then `unset`).
- **`tc-clean`** — remove all resources labelled `org.testcontainers`: force-remove matching containers (includes the ryuk reaper), then prune matching volumes and networks. Prints a count of what it removed; a no-op message when nothing matches. Strictly label-scoped.
- **`tc-ls`** — list running/all containers carrying the `org.testcontainers` label (id, image, name, status), so the owner can see what a test run left behind before cleaning.
- **`dctx`** — switch the active Docker context. With no arg it prints the current context and the available ones; with `rancher`/`desktop` (or a context name) it runs `docker context use <resolved>`. It reads the repo's `docker_runtime` config key for the default target. Guarded by `command -v docker`.
- New helpers follow the file's existing `*-fn` + `alias` convention and get a one-line usage comment in the header block.

### C — SDKMAN per-project env (`setup.sh`, `bin/dot-doctor`)
- **`setup.sh`** gains an idempotent step (guarded by `[[ -f "$HOME/.sdkman/etc/config" ]]`) that ensures `sdkman_auto_env=true`: if the key is already `true`, no-op; if `false`, flip it (BSD `sed -i ''`); if absent, append it. Re-running setup on an existing machine applies it without duplication. Uses `log_*` helpers.
- **`bin/dot-doctor`** gains a check: if SDKMAN is installed and `sdkman_auto_env` is not `true`, emit `log_warning` with the one-line remedy (re-run setup). Green check when on.
- Effect: existing `.sdkmanrc` files (learn-micronaut, idempotence4j, kotlin) auto-apply the right JDK/build versions on `cd`.

### D — JVM tools (`brew/Brewfile.core`)
- Add, each with a trailing comment, in the dev-tools section:
  - `brew 'ktlint'` — Kotlin linter/formatter (complements the already-installed `detekt`).
  - `brew 'async-profiler'` — low-overhead JVM sampling profiler (flame graphs).
  - `cask 'jdk-mission-control'` — GUI to analyse JFR recordings (pairs with the already-present `jfr`); inside the `if OS.mac?` cask block.
- Installed via `dot homebrew bundle`. (All three are core formulae / a standard cask — no third-party tap, unlike `tenv`/`tflint`.)

## 6. Architecture / unit boundaries

Four independent layers, each its own task with its own gate:
- **A** edits one file (`starship.toml`); validated by a starship render in sample project dirs.
- **B** edits one file (`.docker_aliases`); validated by shellcheck + sourcing + label-scoped dry checks. The `tc-*` helpers depend only on the `org.testcontainers` label contract; `dctx` depends only on `docker context` + the `docker_runtime` config reader.
- **C** edits two scripts (`setup.sh`, `dot-doctor`); validated by running the idempotent step twice and the doctor check both ways.
- **D** edits one file (`Brewfile.core`); validated by `brew bundle` resolution.

No shared state across layers — they can ship in any order. The only cross-reference is `dctx` reading the existing `docker_runtime` config key (consumer only, no change to that mechanism).

## 7. Testing & rollout

- **Automated:** `pre-commit run --all-files` (check-toml on starship, shellcheck on `.docker_aliases`/`setup.sh`/`dot-doctor` — note the shellcheck gate now covers `bin/`), `bin/dot test`, `zsh -i -c 'echo ok'`.
- **Tool-resolves:** `starship --version`; after bundle, `ktlint --version`, `async-profiler` present, `jdk-mission-control` app installed.
- **Layer-specific:** A — `starship module kotlin`/`scala` render in a Kotlin and an sbt sample dir, and a Maven dir shows only Java. B — source `.docker_aliases`, run `tc-ls`/`dctx` with no stray side effects; `tc-clean` with no Testcontainers running prints the no-op message. C — run the setup step twice (second run is a no-op), confirm `sdkman_auto_env=true`, then `dot-doctor` shows green; `cd` into a project with `.sdkmanrc` switches the JDK. D — `dot homebrew bundle` then the resolves checks.
- **Rollout:** all repo changes apply via `dot link`; the SDKMAN flip applies by re-running `setup.sh` (or its step) on each machine. No manual macOS permission needed.

## 8. Open implementation details (resolved at plan time, not blockers)

- Exact catppuccin hex + Nerd Font glyph for the Kotlin and Scala starship badges (match the existing `[java]`/`[terraform]` styling).
- The precise `docker context` names on this machine (`rancher-desktop` vs `desktop-linux`/`default`) — `dctx` resolves them at runtime via `docker context ls`, so the helper adapts rather than hardcoding.
- Whether `tc-clean` also prunes dangling images from test builds — default no (volumes + networks + containers only) to stay conservative; revisit if image buildup is a real problem.
