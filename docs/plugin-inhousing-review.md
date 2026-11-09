# Review: small third-party plugins worth bringing in-house

Scope: the `dependencies.data` list in `modules/package.nix`, distribution
entry points and feature APIs as of 9 November 2026. This is **an audit**, not
a request to vendor upstream code or recreate unrelated plugin capabilities.

## Decision criteria

Only internalize behavior when the currently used API is small, stable,
domain-specific and can be implemented from Neovim's existing APIs or an
already installed plugin. A replacement must retain observable behavior, be
tested in the packaged editor, and **remove** its upstream package/input.
Copying a whole plugin into the tree without shrinking the dependency surface
does not count as an improvement.

| Dependency | Current use | Decision | Why |
| --- | --- | --- | --- |
| `pick-resession.nvim` | `phenix.features.session.pick()` calls `require("pick-resession").pick()` | **In-house first** | Only its `Snacks.picker.pick` adapter is used; the upstream Snacks entry point is ~2.9 KB of Lua. It also ships Telescope support we do not use. Implement a local session finder/confirm/delete picker using already-installed `resession.nvim` and Snacks; remove its flake input and plugin derivation. |
| `base16-nvim` | Theme calls `setup("catppuccin-mocha")`, reads `colors`, writes `highlight`; color preview also reads `colors` | **Maybe later** | A fixed palette and highlights could use native `nvim_set_hl`, eliminating the external base16 engine. But it also supplies syntax, Treesitter and LSP theme defaults; do not lose these accidentally. |
| `nvim-web-devicons` | Statusline/tabline query `get_icon` for filenames | **Optional, scope-dependent** | A concise icon registry could cover common files, but the full extension/filetype mapping is broader and other plugins may use it. Only replace if deliberately accepting fallback icons for rare filetypes. |
| `resession.nvim` | Session save, load, list and delete; autosave and restore | **Keep** | Persistent sessions and edge-case recovery are more consequential than a small picker adapter. In-house only when changing the persistence model is independently justified. |
| `nui.nvim` | No direct first-party `require("nui...")` found | **Audit for removal, not in-housing** | May be a transitive dependency of other installed plugins; verify the packaged dependency graph before deleting. |
| `lz-n` | No direct lazy-loader use found in first-party Lua | **Audit for removal, not in-housing** | The distribution eagerly loads its feature packages; a lazy-loading framework without a declared consumer is likely unnecessary. |
| `telescope-nvim` | No first-party Telescope invocation; pick-resession is called via Snacks | **Remove after verifying dependents** | Snacks already provides active picker behavior; do not maintain two picker backends without a feature that needs both. |
| `helpview-nvim`, `markview-nvim` | Help and markup visualizers installed | **Keep / evaluate overlap** | Substantial concealed markup and highlight behavior; not small. Check overlapping filetypes and only remove if features are redundant. |
| `snacks-nvim`, `blink-cmp`, `conform-nvim`, `gitsigns-nvim`, `which-key-nvim`, `nvim-treesitter`, `nvim-lspconfig`, `lazydev-nvim` | Core editor functionality | **Keep** | Broad maintained ecosystems; rebuilding these expands maintenance and breaks integration surface. |

Approximate upstream GitHub repository sizes reported during this review:
`pick-resession.nvim` 42 KB, `resession.nvim` 113 KB,
`base16-nvim` 383 KB, `nvim-web-devicons` 749 KB, and
`snacks.nvim` ~15 MB. These repository figures include non-source assets
and should **not** be treated as installed closure size or Lua LOC.

## Recommended order

1. **Implement only the required session picker** inside
   `phenix.features.session`. Use `require("resession").list()`,
   `require("snacks").picker.pick`, confirm-to-load, Ctrl-D-to-delete,
   and picker refresh. Preserve the current display, empty-list behavior,
   name escaping, and session directory handling. Remove the
   `plugins-pick-resession-nvim` flake input, lock node, Nix derivation and
   reference. Add a real packaged UI interaction test.
2. **Prune provably unused dependencies**, prioritizing `lz-n` and
   `telescope-nvim`. Verify plugin runtime loading/transitive requires
   before each removal; use a package-startup smoke test. `nui.nvim` needs
   an additional dependency check.
3. **Evaluate `base16-nvim` separately.** Capture the actual syntax/LSP
   highlight set and compare against a native theme prototype before
   removing a dependency. Keep color-preview palette semantics intact.
4. **Leave core systems upstream.** Low source size alone is not evidence
   that in-housing improves reliability, compatibility or maintenance.

Avoid copying upstream files verbatim without checking licenses. Prefer a
small original adapter around already installed public APIs.
