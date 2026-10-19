# Phenix Neovim

The complete Phenix Neovim distribution.

This repository owns editor configuration, LSP setup, keymaps, theme/UI composition, and distribution-specific feature plugins. It does not own the Phenix AI client implementation.

The AI integration is consumed from [`matthis-k/phenix-ai.nvim`](https://github.com/matthis-k/phenix-ai.nvim). The distribution also pins [`matthis-k/phenix-ai`](https://github.com/matthis-k/phenix-ai) directly and forces the client to follow that exact revision, so the packaged ACP runtime, Lua binding, frontend, and model/provider configuration advance as one tested dependency unit.

```text
phenix-nvim
  -> phenix-ai.nvim
      -> phenix-ai
```

## P1 Basic default and real-model option

The supported `nvim-nix` default now consumes the standalone M1/P1 Basic
client over ACP v1. Phenix owns the agent loop, session journal, models and
permission authority; this distribution owns Neovim editor behavior only.

- `nvim-nix`: normal Basic agent with the **managed ACP host** and
  read-only native provider registration discovery (`:Phenix providers`).
- `nvim-nix-basic`: explicit Basic-only binary with unchanged ACP behavior,
  without the provider-management extension.
- `nvim-nix-live`: the same UI and runtime-facing bridge with the opt-in
  HTTP Model composition.
- `phenix-p1-live-prompt`: submit a live prompt in headless Neovim and print
  the assistant response on stdout.

All packages use the exact pinned `phenix-ai` and `phenix-ai.nvim` inputs
in `flake.lock`; the client runtime input follows the distribution pin.
No extra provider or session implementation is bundled in Neovim.

```sh
# Deterministic Basic Model, no provider API key required:
nix run .#nvim-nix

# Optional real-model prompt:
export OPENAI_API_KEY="..."  # or PHENIX_MODEL_HTTP_API_KEY
export PHENIX_MODEL_HTTP_MODEL="gpt-4.1-mini"
nix run .#phenix-p1-live-prompt -- "List your available tools"

# Optional full interactive real-model frontend:
nix run .#nvim-nix-live
```

Inside the editor, open `:Phenix new`, compose a prompt, and send it
with Enter in normal mode or by writing the compose buffer.
`:Phenix providers` on the regular `nvim-nix` package lists the
**installed, runtime-contributed provider connections** and their declared
API-key/OAuth method types. This is registration metadata, not authenticated
accounts, available models, or a login operation.
`:Phenix capabilities` shows the runtime-advertised ACP operations and
runtime-selected model. `:Phenix session load <id>` replays journal history.
The HTTP Model defaults to an OpenAI-compatible chat-completions endpoint;
set `PHENIX_MODEL_HTTP_ENDPOINT` to use another compatible service.
Credentialed calls are opt-in and may incur provider charges.

The installed Basic preset stores its private SQLite session/journal
state under `$XDG_STATE_HOME/phenix/basic.sqlite` by default, creating
the state directory automatically. The live HTTP preset uses
`$XDG_STATE_HOME/phenix/basic-http.sqlite`. Set an **absolute**
`PHENIX_BASIC_SQLITE_PATH` before starting Neovim to override either
location. Different presets intentionally retain separate databases.

`:Phenix model` uses the standard ACP model configuration option. The
currently admitted model can be reselected, but switching to another
provider/account is not yet implemented. `:Phenix auth` is registered,
but interactive credential import/OAuth is not functional until runtime
management issue #891 is complete. For now, the live HTTP preset reads
`OPENAI_API_KEY` or `PHENIX_MODEL_HTTP_API_KEY` from the launch
environment. Runtime-managed account selection, persisted-session
enumeration and close, and client-contributed tools remain open.
Unavailable controls report unsupported and do not fall back to the
legacy Neovim runtime. The [distribution roadmap](spec/p1-p2-distribution-roadmap.md)
tracks post-P1 authorized management and Advanced/A2UI features.

The Nix package installs `phenix-ai.nvim` as an external plugin.
Frontend-neutral behavior belongs exclusively in `phenix-ai`.

## Neovim module ownership

Distribution shortcuts invoke the installed editor feature modules directly
(`phenix.features.picker`, `phenix.features.notifier`,
`phenix.features.lsp`, etc.). Status bars use the Git feature module and the
public `phenix_nvim.status.get()` projection. No global `Phenix.api` registry,
`phenix.frontend` facade, or kernel-specific behavior is required for editor
features.

The default runtime is P1 Basic. The editor feature modules do not expose
or reimplement its graph, model provider, permission or session contracts.
