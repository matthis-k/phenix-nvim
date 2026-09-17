# Phenix Neovim

The complete Phenix Neovim distribution.

This repository owns editor configuration, LSP setup, keymaps, theme/UI composition, and distribution-specific feature plugins. It does not own the Phenix AI client implementation.

The AI integration is consumed from [`matthis-k/phenix-ai.nvim`](https://github.com/matthis-k/phenix-ai.nvim), which in turn depends on [`matthis-k/phenix-ai`](https://github.com/matthis-k/phenix-ai) for the generic runtime and supported default Harness.

```text
phenix-nvim
  -> phenix-ai.nvim
      -> phenix-ai
```

The Nix package installs and configures `phenix-ai.nvim` as an external plugin. Neovim-specific AI behavior belongs in `phenix-ai.nvim`; frontend-neutral runtime behavior belongs in `phenix-ai`.
