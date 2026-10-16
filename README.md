# Phenix Neovim

The complete Phenix Neovim distribution.

This repository owns editor configuration, LSP setup, keymaps, theme/UI composition, and distribution-specific feature plugins. It does not own the Phenix AI client implementation.

The AI integration is consumed from [`matthis-k/phenix-ai.nvim`](https://github.com/matthis-k/phenix-ai.nvim). The distribution also pins [`matthis-k/phenix-ai`](https://github.com/matthis-k/phenix-ai) directly and forces the client to follow that exact revision, so the packaged ACP runtime, Lua binding, frontend, and model/provider configuration advance as one tested dependency unit.

```text
phenix-nvim
  -> phenix-ai.nvim
      -> phenix-ai
```

## Opt-in P1 with a real model

The standalone [Neovim client PR #48](https://github.com/matthis-k/phenix-ai.nvim/pull/48)
and [runtime PR #933](https://github.com/matthis-k/phenix-ai/pull/933)
add the following optional outputs. The normal `nvim-nix` remains the
default while the P1 cutover is verified.

- `nvim-nix-basic`: P1 client connected to the deterministic scripted Model.
- `nvim-nix-live`: the same UI and plugins, connected to the P1 HTTP Model.
- `phenix-p1-live-prompt`: submit a prompt through the installed live P1 client
  in headless Neovim and print its response.

The default flake lock still targets the legacy product. From a checkout
of this PR, use the **same exact runtime and client revisions as P1 CI**
until the lock is promoted. Otherwise these optional outputs are not yet
available through an unmodified `nix run .#...`.

```bash
p1_inputs=(
  --override-input phenix-ai github:matthis-k/phenix-ai/8ad88aec18c34034beb53afc385af370771488b3
  --override-input phenix-ai-nvim github:matthis-k/phenix-ai.nvim/dfd8e87dfe36829f9a71af5078b3634b5f9523c7
)
export OPENAI_API_KEY="..."   # or PHENIX_MODEL_HTTP_API_KEY
export PHENIX_MODEL_HTTP_MODEL="gpt-4.1-mini"

# One real-model prompt, answer on stdout, session/model details on stderr:
nix run "${p1_inputs[@]}" .#phenix-p1-live-prompt -- "List your available tools and try one"

# Full existing editor UI using exactly the same P1 composition:
nix run "${p1_inputs[@]}" .#nvim-nix-live
# Or use .#nvim-nix-basic for the deterministic scripted model (no API key).
```

In the interactive editor, open `:Phenix new`, submit a prompt in the
compose window, and use
`:Phenix capabilities` to inspect supported ACP operations and the
runtime-selected Model. Only capabilities reported by Phenix are shown.
This is an opt-in live API test and may incur provider charges.

Set `PHENIX_MODEL_HTTP_ENDPOINT` for another OpenAI-compatible
chat-completions provider. Credentials are read from the process
environment at runtime; Nix package expressions contain no secrets.
The upstream P1 ACP client still lacks arbitrary model/routing mutations
and full Advanced UI support. The [P1-to-P2 distribution roadmap](spec/p1-p2-distribution-roadmap.md)
tracks the remaining work.

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
