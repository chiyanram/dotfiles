# Dotfiles Neovim Overhaul — Implementation Plan (Plan 11)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Trim the `nicknisi`/web-fork cruft from the Neovim config, fix its active bugs + deprecations, and add the Java / Terraform / Kubernetes language tooling the owner actually uses — turning a copied fork into a config that fits a Java/Spring/Gradle/K8s/Terraform backend engineer.

**Architecture:** The config is a lazy.nvim setup with a sound lua architecture (blink.cmp, snacks, gitsigns, telescope, treesitter). This plan is **trim-to-fit**, not a rebuild. The detailed findings + fixes are in `docs/audit/config-audit.md` §2 — that document is the spec for each task; this plan groups the work and sets the gate.

**Tech Stack:** Neovim (lua + lazy.nvim + mason), bats (for the bash gate only).

## Global Constraints
- macOS-only; the nvim config is verified LOCALLY (nvim isn't in CI). The **load gate** for every task: `nvim --headless "+qa"` exits 0 with NO new errors (baseline today exits 0 with one pre-existing `vim.lsp.with()` deprecation, which Task 2 fixes).
- `bin/dot test` must stay green (nvim changes don't affect the bash gate, but run it to confirm no collateral). Conventional Commits; no `Co-Authored-By`.
- Keep lua clean and consistent with the existing `nisi` module style. Don't restructure the architecture; make surgical edits.
- **Manual verification (note in each report, for the owner to confirm in-editor):** open a Java file → `jdtls` attaches; open a `.tf` → `terraformls`; open a K8s YAML → schema completion. `+qa` proves the config LOADS; it can't prove an LSP attaches.

## Reference spec
`docs/audit/config-audit.md` §2 (Neovim) — the per-item remove/add/fix list. Each task below names which §2 items it covers; read that section first.

---

## Task 1: Trim the web/PHP/Ruby fork cruft

Covers config-audit §2 "High — remove web/PHP/Ruby cruft" + the legacy-vimscript Med/Low items.

**Files (read first):** `config/nvim/lua/nisi/plugins/lsp/config.lua`, `lsp/init.lua`, `treesitter.lua`, `files.lua`, `ui.lua`, `core.lua`, `snippets.lua`; `config/nvim/after/queries/blade/*`, `config/nvim/snippets/{javascript,typescript}.json`, `config/nvim/plugin/{hiinterestingword,zoom,winmove,applylocalsettings}.vim`, `config/nvim/autoload/functions.vim`, `config/nvim/ftplugin/{ruby,html}.vim`, `config/nvim/ftdetect/html.vim`, `config/nvim/lua/nisi/config/keymaps.lua`.

- [ ] **Step 1: Remove the web/PHP/Ruby LSP + formatter + parser cruft**
  - LSP `servers`: remove `eslint`, `ts_ls`, `denols`, `astro`, `intelephense`, `tailwindcss`, `ruby_lsp`.
  - conform formatters: strip JS/TS/CSS/Ruby/PHP entries (prettier/stylelint/rubocop/pint); keep `sh`/`python`/`go`/`lua`.
  - treesitter `ensure_installed`: remove `astro`, `blade`, `pug`, `ruby`, `tsx`, `typescript`, `jsdoc`, `json5`, `css` (+ the custom blade parser registration).
  - `git rm -r config/nvim/after/queries/blade/`.

- [ ] **Step 2: Remove the dead web plugins + snippets**
  - Remove `vuki656/package-info.nvim` (npm), `telescope-node-modules.nvim` + its `<leader>fn` keymap, `tpope/vim-ragtag`, `nvim-treesitter/playground` (archived; `:InspectTree` replaces it), and `nvim-colorizer`'s `tailwind = true`.
  - `git rm config/nvim/snippets/javascript.json config/nvim/snippets/typescript.json`.

- [ ] **Step 3: Remove the legacy vimscript that duplicates the lua setup**
  - `git rm config/nvim/plugin/hiinterestingword.vim config/nvim/plugin/zoom.vim config/nvim/plugin/winmove.vim config/nvim/plugin/applylocalsettings.vim config/nvim/autoload/functions.vim config/nvim/ftplugin/ruby.vim config/nvim/ftplugin/html.vim config/nvim/ftdetect/html.vim`.
  - In `keymaps.lua`, remove the now-orphaned keymaps for the deleted plugins (hiinterestingword `<leader>0-6`, zoom `<leader>z`, winmove `<C-h/j/k/l>` if they referenced the vimscript). Replace window-nav with native `<C-w>h/j/k/l` if needed.

- [ ] **Step 4: Verify nvim loads clean**

Run: `nvim --headless "+qa" 2>&1; echo "exit=$?"`
Expected: `exit=0`, NO new errors (a missing-plugin error or orphaned-keymap error means a reference was missed — fix it). The pre-existing `vim.lsp.with()` deprecation may still appear (Task 2 fixes it).

Run: `bin/dot test` → `All checks passed`.

- [ ] **Step 5: Commit**

```bash
git add -A config/nvim
git commit -m "refactor(nvim): trim web/PHP/Ruby fork cruft and legacy vimscript"
```

---

## Task 2: Fix the active bugs + deprecations

Covers config-audit §2 "High — active bugs" + the Med/Low bug items.

- [ ] **Step 1: Fix the three active bugs**
  - `statusline.lua`: remove the `require("lazyvim.util").deprecate(...)` block (this is NOT LazyVim — it errors if `lazyvim` is absent).
  - `extras/copilot.lua`: remove `copilot-cmp` (hard-depends on the commented-out `nvim-cmp`); rely on copilot's native `suggestion` mode.
  - `snippets.lua`: remove `vim-vsnip`/`cmp-vsnip`/`vim-vsnip-integ` deadweight (blink.cmp is active); point blink's snippets at the dotfiles `snippets/` dir (`snippets.paths`).

- [ ] **Step 2: Fix deprecations + duplicates**
  - `utils.lua`: `vim.loop` → `vim.uv`; `vim.lsp.get_active_clients()` → `vim.lsp.get_clients()`.
  - Fix the `vim.lsp.with()` deprecation (baseline warning) per `:checkhealth vim.deprecated` (usually the diagnostics/hover handler setup → use the new `vim.diagnostic.config`/handler API).
  - `lsp/config.lua`: remove the duplicate `"pylsp"` entry; remove the dead `diagnosticls` handler block + the stray `vim.notify("Using new definition handler")`.
  - `keymaps.lua`: collapse the 5× duplicate `<C-s>`/`<D-s>` bindings to one each.
  - `extras/python.lua`: remap sniprun off `<leader>sr` (collides with spectre) → `<leader>pr`.
  - `init.lua`: change `startup_art` from the `nicknisi` default to `"neovim"` (or remove the nicknisi art from `assets.lua`).

- [ ] **Step 3: Verify nvim loads clean (no deprecations)**

Run: `nvim --headless "+qa" 2>&1; echo "exit=$?"`
Expected: `exit=0` and NO deprecation warning (the `vim.lsp.with()` line is gone). Run: `bin/dot test` → green.

- [ ] **Step 4: Commit**

```bash
git add -A config/nvim
git commit -m "fix(nvim): remove lazyvim/copilot-cmp/vsnip bugs and deprecated APIs"
```

---

## Task 3: Add Java tooling (jdtls + DAP)

Covers config-audit §2 #20, #25 — the single highest-value addition.

- [ ] **Step 1: Add `nvim-jdtls` + jdtls**
  - Add the `mfussenegger/nvim-jdtls` plugin (lazy spec, `ft = "java"`).
  - Configure jdtls with project-root detection for Gradle/Maven (`gradlew`/`mvnw`/`.git`), a per-project workspace dir under `vim.fn.stdpath("cache")`, and mason-installed `jdtls`.
  - Add `jdtls` to the mason `ensure_installed` (NOT to mason-lspconfig's `servers` handler — jdtls is started by nvim-jdtls, not lspconfig).
  - Wire Java DAP via jdtls' bundles (`java-debug-adapter`, `java-test` from mason) into the existing `nvim-dap`/`nvim-dap-ui` setup.

- [ ] **Step 2: Verify**

Run: `nvim --headless "+qa" 2>&1; echo "exit=$?"` → `exit=0`.
Run: `nvim --headless "+Lazy! install" +qa 2>&1 | tail -5; echo "exit=$?"` → installs the new plugin without error (network).
Note in the report: jdtls-attaches-to-a-Java-file is a MANUAL check for the owner (open a `.java` in a Gradle project → `:LspInfo` shows jdtls).
Run: `bin/dot test` → green.

- [ ] **Step 3: Commit**

```bash
git add -A config/nvim
git commit -m "feat(nvim): add Java LSP (nvim-jdtls) with DAP"
```

---

## Task 4: Add Terraform + YAML/K8s + Helm + treesitter

Covers config-audit §2 #21, #22, #23, #24, #16(add).

- [ ] **Step 1: Add the LSPs + formatters + parsers**
  - LSP `servers`: add `terraformls`, `yamlls`, `helm_ls`. Add `tflint` (mason) + `terraform_fmt` (conform) for Terraform; `yamlfmt` for YAML.
  - `yamlls`: wire `b0o/schemastore.nvim` and point its YAML schemas at Kubernetes / Helm-values / GitHub-Actions schemas (kubernetes schema for `*.k8s.yaml`/manifests).
  - treesitter `ensure_installed`: add `java`, `hcl`, `dockerfile`, `sql`.

- [ ] **Step 2: Verify**

Run: `nvim --headless "+qa" 2>&1; echo "exit=$?"` → `exit=0`.
Run: `nvim --headless "+Lazy! install" +qa 2>&1 | tail -5; echo "exit=$?"` and `nvim --headless "+TSUpdate" +qa 2>&1 | tail -3` → install cleanly (network).
Note manual checks (open `.tf` → terraformls; K8s YAML → schema completion).
Run: `bin/dot test` → green.

- [ ] **Step 3: Commit**

```bash
git add -A config/nvim
git commit -m "feat(nvim): add terraform, yaml+k8s schemas, helm, and treesitter parsers"
```

---

## Done criteria
- `nvim --headless "+qa"` exits 0 with NO errors and NO deprecation warnings.
- LSP servers/formatters/parsers no longer include any web/PHP/Ruby entries; the blade queries and JS/TS snippets and the 8 legacy vimscript files are gone; the 3 active bugs are fixed.
- `nvim-jdtls` (Java + DAP), `terraformls`+`tflint`, `yamlls`+schemastore(K8s)+`helm_ls`, and treesitter `java/hcl/dockerfile/sql` are added.
- `bin/dot test` stays green. (Owner manually confirms in-editor that jdtls/terraformls/yamlls attach.)
