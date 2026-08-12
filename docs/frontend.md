# Phenix Neovim

`phenix-nvim` is both the complete Phenix Neovim distribution and a collection of independently consumable feature plugins. The ACP/conductor repository owns protocol, routing, workflows, backend integration, and runtime orchestration; this repository owns Neovim-facing UX.

## Feature collection

The collection follows a mini.nvim-style boundary: a feature gets its own plugin when it has a coherent user-facing responsibility, public interface, and lifecycle that can be enabled, replaced, or tested independently. Basic `vim.opt` policy and the final distribution keymap choices remain distribution configuration rather than artificial plugins.

The current collection is:

- `phenix-ui`: implementation-agnostic frontend utilities, typed interface registry, and global Phenix config/state;
- `phenix-acp`: thin Neovim frontend wrapper for the Phenix ACP harness;
- `phenix-bars`: statusline, tabline, statuscolumn rendering and composition primitives;
- `phenix-color-preview`: palette preview UI;
- `phenix-picker`: picker/search/navigation frontend;
- `phenix-session`: editor session lifecycle and session picker bridge;
- `phenix-theme`: Phenix theme/highlight policy;
- `phenix-git`: Git editor integration;
- `phenix-lsp`: LSP editor integration;
- `phenix-completion`: completion integration;
- `phenix-dashboard`: dashboard frontend;
- `phenix-explorer`: file explorer frontend;
- `phenix-terminal`: terminal frontend;
- `phenix-notify`: notification frontend.

Each is exported as its own flake package (`phenix-*-plugin`). The default wrapped editor loads the collection and then applies the small amount of distribution policy that composes the features.

OpenCode is not part of the distribution. `phenix-acp` is the harness frontend and owns the agent interaction surface.

## Shared typed frontend runtime

`phenix-ui` initializes one global registry:

```lua
---@class PhenixGlobal
---@field config table<string, any>
---@field state table<string, any>
---@field interfaces PhenixInterfaces
_G.Phenix = Phenix
```

The public shape is:

```lua
Phenix.config.<feature>
Phenix.state.<feature>
Phenix.interfaces.<feature>
Phenix.interface("picker")
Phenix.provide("feature", implementation)
```

Interfaces are backed by `PhenixInterface<T>` objects. Implementations can declare runtime contracts while LuaLS annotations describe the concrete feature API, so late-bound interfaces still provide useful completion and type information. `phenix-ui` itself does not import Snacks, Resession, or other concrete frontend implementations.

For example, distribution mappings resolve through the typed picker, LSP, terminal, notifier, explorer, dashboard, and session interfaces. The ACP frontend registers itself as `Phenix.interfaces.acp`, while its current session is projected into `Phenix.state.acp.session`. Concrete shared backend configuration such as `Snacks.setup()` remains in the distribution integration layer, before the semantic feature wrappers bind their interfaces.

`phenix.frontend.window` contains shared window helpers. The ACP frontend consumes that shared utility through its existing `phenix.window` boundary rather than carrying another copy of generic frontend code.

## Dependency direction

The dependency direction is intentionally narrow:

```text
Neovim distribution policy
        |
        v
feature plugins -----> phenix-ui
        |
        +-----> third-party implementation plugins where needed

phenix-acp -----> phenix-ui -----> shared frontend utilities
        |
        +-----> phenix-conductor over ACP stdio
```

Feature plugins must not import `phenix_distribution`. Distribution configuration may compose feature APIs, but features remain independently packageable.

## Bars

`phenix-bars` owns rendering, click dispatch, status-surface lifecycle, and generic statuscolumn primitives. A surface is a declarative part tree whose values may be callbacks:

```lua
require("phenix.bars").configure({
  statusline = {
    children = {
      { text = function() return vim.bo.filetype end },
      { text = "%=" },
      { text = "%l:%c" },
    },
  },
})
```

The top-level API exposes `render_part()` and `register_click()`. `require("phenix.bars.statuscolumn")` exposes configurable sign columns, `sign_part()`, `number_part()`, `fold_part()`, cache invalidation, and a replaceable fold-information provider. Gitsigns invalidation remains an integration concern rather than being hardcoded into the generic statuscolumn implementation.

## Phenix ACP frontend

`phenix-acp` is a thin Neovim wrapper around the Phenix ACP harness. It communicates with `phenix-conductor` over ACP stdio and does not own routing execution, workflows, downstream ACP sessions, or backend selection.

Its public Lua interface is also available as `Phenix.interface("acp")` and exposes `setup()`, `toggle()`, `maximize()`, `cancel()`, `current()`, and `shutdown()`.

The plugin itself exposes `<Plug>` actions only:

- `<Plug>(phenix-toggle)`;
- `<Plug>(phenix-open-fullscreen)`;
- `<Plug>(phenix-open-fullscreen-tab)`;
- `<Plug>(phenix-maximize)`;
- `<Plug>(phenix-cancel)`;
- `<Plug>(phenix-shutdown)`.

`setup()` only configures the frontend. User mappings are distribution policy. The default distribution maps them under `<leader>p` (`p`, `pf`, `pt`, `pm`, `pc`) by remapping to the public `<Plug>` targets.

## Input and transcript

The ACP input is a normal editable `acwrite` buffer:

- Normal `<CR>` sends;
- Normal `<S-CR>` steers the active response;
- Normal `<M-CR>` queues a follow-up;
- `:write` sends;
- Insert `<CR>` remains a newline.

The prompt grows and shrinks within configured bounds. Queued follow-ups use a dedicated adaptive window. Closing either the prompt or transcript closes the UI group without terminating the ACP session.

The transcript is an unmodifiable Markdown buffer. Markdown rendering is delegated to Markview when available. User, assistant, thinking, system/error, and tool blocks remain semantically distinct. Thinking and tool details use native folds with custom previews; streamed updates preserve cursor/viewport position and fold state. Tool parameters remain structured until rendering so multiline values are represented as real multiline Markdown/code blocks.

ACP stdout is coalesced and drained in bounded scheduled batches. Each decoded frame has an independent error boundary, so one broken notification/UI callback cannot discard a later response frame and leave a prompt permanently pending.

Cancellation sends standard `session/cancel`, clears queued follow-ups, and keeps the frontend session state synchronized with the global `Phenix.state.acp` projection.
