# Phenix Neovim

The complete Phenix Neovim distribution.

This repository owns editor configuration, LSP setup, keymaps, theme/UI composition, and distribution-specific feature plugins. It does not own the Phenix AI client implementation.

The AI integration is consumed from [`matthis-k/phenix-ai.nvim`](https://github.com/matthis-k/phenix-ai.nvim). The distribution also pins [`matthis-k/phenix-ai`](https://github.com/matthis-k/phenix-ai) directly and forces the client to follow that exact revision, so the packaged ACP runtime, Lua binding, frontend, and model/provider configuration advance as one tested dependency unit.

```text
phenix-nvim
  -> phenix-ai.nvim
      -> phenix-ai
```

## P1 default: authenticate from Neovim

`packages.default` and `nvim-nix` now use the combined P1 native ACP
authentication product. Phenix owns the agent loop, session journal, providers,
credentials, model selection and permission authority; this distribution owns
Neovim editor behavior only.

- `nvim-nix` / `default`: API key (masked direct entry or environment-variable
  name) and ChatGPT browser OAuth through one native `:Phenix auth` workflow.
- `nvim-nix-managed`: the previous metadata-only managed ACP host, with
  `:Phenix providers` but without credential-write authority.
- `nvim-nix-basic`: deterministic Basic agent for offline tests and fallback,
  without provider-management extensions.
- `nvim-nix-live`: the same UI and runtime-facing bridge with the opt-in
  HTTP Model composition.
- `nvim-nix-openai-api` (opt-in): the independently authorized OpenAI
  API-key provider, current provider-side verification and model selection.
  It is available only when the pinned client/runtime pair provides it.
- `nvim-nix-p1-auth`: explicit alias of the combined P1 auth composition
  also used by the default editor; model selection and provider-owned sign-out
  are available in both.
- `phenix-p1-live-prompt`: submit a live prompt in headless Neovim and print
  the assistant response on stdout.

All packages use the exact pinned `phenix-ai` and `phenix-ai.nvim` inputs
in `flake.lock`; the client runtime input follows the distribution pin.
No extra provider or session implementation is bundled in Neovim.

```sh
# Default editor, authenticate interactively once:
nix run .#nvim-nix

# Offline deterministic Basic Model, no provider API key:
nix run .#nvim-nix-basic

# Optional real-model prompt:
export OPENAI_API_KEY="..."  # or PHENIX_MODEL_HTTP_API_KEY
export PHENIX_MODEL_HTTP_MODEL="gpt-4.1-mini"
nix run .#phenix-p1-live-prompt -- "List your available tools"

# Optional full interactive real-model frontend:
nix run .#nvim-nix-live

# Experimental, verified OpenAI API-key provider (no key in the shell):
mkdir -p "$HOME/.local/state/phenix/openai-api-credentials"
chmod 700 "$HOME/.local/state/phenix/openai-api-credentials"
export PHENIX_CREDENTIAL_FILE_DIRECTORY="$HOME/.local/state/phenix/openai-api-credentials"
export PHENIX_CREDENTIAL_FILE_CONSENT=1
nix run .#nvim-nix-openai-api
```

The default package requires **no credential configuration in Nix**, and no
credential environment variables or manual directory creation before launch.
Run `:Phenix auth` inside Neovim, select OpenAI API or ChatGPT, then enter
a key in the masked prompt or complete browser OAuth. Authentication is a
one-time interactive setup: credentials persist across Neovim restarts and are
revalidated as necessary by the provider. Choosing an environment-variable
*name* instead requires that environment variable to be available when used.

The native launcher creates a private (0700) credential directory at
`$XDG_STATE_HOME/phenix/p1-auth-credentials` (default
`~/.local/state/phenix/p1-auth-credentials`), outside the Nix store.
This file backend is permission-protected but **not encrypted at rest**;
explicit `PHENIX_CREDENTIAL_FILE_CONSENT=0` denies storage. No keys, access
tokens, or refresh tokens belong in `flake.nix`, `flake.lock` or Nix options.
SOPS-based provisioning may be added later, but is not required or configured
by the default package.

Inside the editor, run `:Phenix auth`, then `:Phenix model` to choose a verified
provider model **before** starting a session. Use `:Phenix new` afterward:
the connection-level default is adopted by the new session, and you can
compose/send a prompt with Enter in normal mode or in the compose buffer.
`:Phenix providers` lists the installed runtime-contributed connections
and declared authentication methods. Registration metadata does not itself
establish an authenticated account; use `:Phenix auth` to configure one.
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

`:Phenix model` works before `:Phenix new`: the runtime returns authorized
model offers and typed denial reasons without implicitly creating a session.
Selecting an offered model sets a connection-level default, which is revalidated
and adopted by the next session. Inside a session, it uses the runtime-authorized
ACP configuration option to override that session only. The separate `phenix.model.http`
plugin is a legacy transport preset, not a ChatGPT model ID. The `nvim-nix-live` legacy HTTP test preset still uses
`OPENAI_API_KEY` or `PHENIX_MODEL_HTTP_API_KEY` from its environment.

The opt-in `nvim-nix-openai-api` instead enables `:Phenix auth` for
the **single explicitly authorized** `openai/api/personal` credential
profile. Enter the API key using Neovim's masked input; Phenix stores it in
the explicitly consented file backend outside the Nix store. Successful
storage is **not** authentication: the native provider must verify the key
against OpenAI before the account is marked authenticated. Create an active session with `:Phenix new`, then use
`:Phenix model` to select a currently offered Responses model and send a
prompt. The model picker works before session creation and does not create a session implicitly.
Restart and `:Phenix auth revoke openai api personal`
must invalidate the selected credential. The profile store is an explicitly
opted-in, locally protected file fallback **not encrypted at rest**.
Do not use this preset for another provider/account, or assume model
discovery guarantees inference quota. This API-only preset does not implement
ChatGPT subscription OAuth; use the default `nvim-nix` package instead.
See [Authentication UX acceptance](docs/auth-ux-test.md) for real API-key
and ChatGPT OAuth acceptance procedures. The opt-in API-only preset has its own durable
`$XDG_STATE_HOME/phenix/basic-openai-api.sqlite` journal.

In the default `nvim-nix` (or explicit `nvim-nix-p1-auth`), run `:Phenix auth` to choose the runtime-advertised
OpenAI API connection or ChatGPT browser OAuth. OAuth tokens remain with the
provider/authorized credential backend, not the Neovim client. Create a
session with `:Phenix new` after `:Phenix model` (or select a session-specific
model later). Use
`:Phenix auth revoke openai chatgpt personal` to sign out that exact account.
If remote sign-out cannot be confirmed, the UI reports that credentials were
removed locally **without claiming server-side revocation**. The opt-in file
store relies on filesystem protections and is not encrypted at rest. OAuth
entitlement, real inference, refresh and remote logout still require a
user-run test with an eligible account, not just deterministic CI.

Arbitrary additional account identities, full cross-provider routing,
persisted-session enumeration and close, and client-contributed tools remain
separate work.
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
