# Phenix Neovim

The complete Phenix Neovim distribution.

This repository owns editor configuration, LSP setup, keymaps, theme/UI composition, and distribution-specific feature plugins. It does not own the Phenix AI client implementation.

The AI integration is consumed from [`matthis-k/phenix-ai.nvim`](https://github.com/matthis-k/phenix-ai.nvim). The distribution also pins [`matthis-k/phenix-ai`](https://github.com/matthis-k/phenix-ai) directly and forces the client to follow that exact revision, so the packaged ACP runtime, Lua binding, frontend, and model/provider configuration advance as one tested dependency unit.

```text
phenix-nvim
  -> phenix-ai.nvim
      -> phenix-ai
```

The Nix package installs and configures `phenix-ai.nvim` as an external plugin. Neovim-specific AI behavior belongs in `phenix-ai.nvim`; frontend-neutral runtime behavior belongs in `phenix-ai`.

## Neovim module ownership

Distribution shortcuts invoke the installed editor feature modules directly
(`phenix.features.picker`, `phenix.features.notifier`,
`phenix.features.lsp`, etc.). Status bars use the Git feature module and the
public `phenix_nvim.status.get()` projection. No global `Phenix.api` registry,
`phenix.frontend` facade, or kernel-specific behavior is required for editor
features.

The AI client's migration to the M1/P1 minimal-rewrite runtime is owned by
`phenix-ai.nvim` and its ACP client package, not by distribution shortcuts.
Until that package is migrated, the existing pinned distribution product still
uses the legacy AI-client artifact. The editor module changes here do not make
that runtime dependency compatible with the minimal rewrite.
