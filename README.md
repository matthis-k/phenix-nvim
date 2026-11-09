# Phenix Neovim

A Nix-packaged, keyboard-first Neovim distribution. This repository owns its
editor settings, keymaps, LSP integration, completion, theme, statusline,
tabline, statuscolumn, and reusable `phenix-*` feature plugins.

**Phenix AI is not installed or required.** Its standalone Neovim client and
runtime may be integrated separately in a future change.

## Run

```sh
nix run .#nvim-nix
```

The default package uses the pinned Neovim nightly, a Nix-built plugin set,
and XDG-compatible editor configuration. No model provider, credential
directory, AI session store, or agent runtime is started.

## Editor features

- LSP, diagnostics, code actions and compact language-server progress beside diagnostics.
- blink.cmp completion, conform.nvim formatting, Treesitter and keyboard shortcuts.
- Git status and signs, composable bars and Neovim-native fold rendering.
- Snacks-based picking, dashboard, explorer, terminal and notification UI.
- Sessions, palette preview, Catppuccin Mocha-based theme and modular keymaps.

The reusable statusline engine is `phenix-bars`; the distribution selects
content via `lua/phenix_distribution/config/bars.lua`. Feature packages
are under `pack/phenix/opt/`, and the distribution entry point is
`plugin/phenix-distribution.lua`.

## Validation

```sh
nix run .#phenix-source-maintenance -- check
nix run .#phenix-test-maintenance -- test
```

The second command runs the packaged editor headlessly, including isolated
bars tests, LSP progress regressions, keymap checks, and startup. The single
CI workflow runs source and distribution checks on all PRs.

See [the small-plugin in-housing review](docs/plugin-inhousing-review.md)
for candidates, tradeoffs and a recommended adoption order.
