# Phenix Neovim

`phenix-nvim` owns both the complete Phenix Neovim distribution and the independently consumable Phenix frontend plugin. The ACP/conductor repository owns protocol, routing, workflows, backend integration, and runtime state.

## Distribution boundary

The default `phenix-nvim` package is the full editor configuration ported from `matthis-k/nvim-flake`. It targets Neovim nightly, while packaging is implemented with `nix-wrapper-modules`. The wrapper supplies the immutable Neovim build, third-party plugins, runtime tools, libraries, and language providers; Lua remains the source of truth for editor behavior.

The runtime has two deliberately different layers:

- **mechanism packages** under `pack/phenix/opt`, for reusable behavior owned by this repository;
- **distribution configuration** under `lua/phenix_distribution`, which configures Neovim, third-party plugins, and those mechanism APIs.

Only two editor mechanisms are local optional packages: `phenix-bars`, the generic statusline/tabline/statuscolumn engine, and `phenix-color-preview`, the palette-preview window/action. Options, theme, sessions, Snacks, keymaps, Git, LSP, completion, and OpenCode are configuration of Neovim or external plugins and therefore remain configuration rather than being wrapped in artificial local packages.

`plugin/phenix-distribution.lua` activates local mechanisms and applies early Neovim/theme policy. `after/plugin/phenix-distribution.lua` then applies third-party integration policy in one explicit order after normal plugin entrypoints have been sourced. This avoids encoding dependencies in runtimepath/package ordering. Mechanism packages never import distribution modules; configuration may integrate mechanisms with other plugins, but the dependency direction is one-way.

The reusable mechanisms are also exported independently as `phenix-bars-plugin` and `phenix-color-preview-plugin`. The Phenix ACP frontend is a separate filtered package exported as `phenix-nvim-plugin`. Consumers can therefore take one mechanism or the ACP frontend without inheriting the complete editor distribution.

The packaged editor also supplies `phenix-conductor`, `pi-acp`, and the store-backed Phenix orchestration configuration required to initialize a real ACP session.

## Local plugin APIs

Local plugin entrypoints are intentionally small and self-initializing. Configuration functions mutate configuration only; they are not required to make a plugin loadable.

`phenix-bars` owns rendering, click dispatch, status-surface lifecycle, and generic statuscolumn primitives. A surface is a declarative part tree whose values may be callbacks, so distribution code or another plugin can provide live data without the renderer depending on that integration:

```lua
require("phenix.bars").configure({
  statusline = {
    children = {
      { text = function() return require("some-plugin").status() end },
      { text = "%=" },
      { text = "%l:%c" },
    },
  },
})
```

The top-level API exposes `render_part()` for composition and `register_click(name, callback)` for named click handlers. `require("phenix.bars.statuscolumn")` additionally exposes configurable sign columns, `sign_part()`, `number_part()`, `fold_part()`, cache invalidation, and a replaceable fold-information provider. Third-party integrations own their refresh hooks and call the generic invalidation API; for example, the distribution listens for Gitsigns updates rather than teaching `phenix-bars` about Gitsigns.

`phenix-bars` itself has no dependency on Git, devicons, diagnostics policy, the theme, or Phenix ACP state. Those choices are composed by the distribution.

`phenix-color-preview` exposes `require("phenix.color_preview").configure(...)`, `toggle()`, `close()`, and `is_open()`. Its plugin entrypoint publishes `<Plug>(phenix-color-preview-toggle)` instead of selecting a user key. The distribution supplies its Base16 palette and border integration and maps its preferred user key to that `<Plug>` target.

## Phenix UI surface

The frontend plugin communicates with `phenix-conductor` over ACP stdio. It must not depend on plugin source exported from the ACP repository.

The frontend exposes actions through Lua and `<Plug>` targets rather than user commands. Default normal-mode keymaps are grouped under `<leader>p`:

- `<leader>p`: toggle the UI;
- `<leader>pf`: open the UI fullscreen in the current tab;
- `<leader>pt`: open the UI fullscreen in a new tab;
- `<leader>pm`: toggle the prompt-only maximized view;
- `<leader>pc`: cancel the active response.

Integrations can map the corresponding normal-mode `<Plug>` targets instead of calling Lua: `<Plug>(phenix-toggle)`, `<Plug>(phenix-open-fullscreen)`, `<Plug>(phenix-open-fullscreen-tab)`, `<Plug>(phenix-maximize)`, `<Plug>(phenix-cancel)`, and `<Plug>(phenix-shutdown)`.

`require("phenix").toggle({ ... })` accepts the same options as `setup`, with per-call values taking precedence. By default it opens a right-hand UI at 50% of the editor width and gives the prompt 25% of the editor height, clamped between 4 and 12 lines. `width` and `input_height` accept either an absolute number of cells/lines or a fraction from zero to one; `input_height_min` and `input_height_max` set the prompt bounds. The follow-up queue has matching `follow_up_height`, `follow_up_height_min`, and `follow_up_height_max` options. Set `fullscreen = true` to close other windows in the target tab before opening, or `tab = true` to open and switch to a new tab first.

The action opens one right-hand sidebar composed of exactly two Neovim windows:

- transcript;
- input.

Toggling the sidebar only hides or recreates those windows. It does not terminate the conductor process or discard the current transcript/input buffers.

## Input and execution

The input is a normal editable `acwrite` buffer.

- Normal `<CR>` sends the prompt.
- Normal `<S-CR>` steers the active response.
- Normal `<M-CR>` queues a follow-up for the next turn.
- `:write` sends the prompt.
- Insert `<CR>` remains a normal newline.

The prompt window grows and shrinks to fit its wrapped visual lines within its configured bounds. Queued follow-ups appear in an automatically managed window between the transcript and prompt, using the same adaptive sizing behavior; it opens when work is queued and closes after the queue drains. `require("phenix").maximize()` toggles a prompt-only view; submitting by any send action restores the normal transcript-and-prompt view.

Steering uses the existing Phenix session-tree `Steer` operation. Follow-ups entered while a response is active are queued and submitted as the next ordinary ACP prompt. `require("phenix").cancel()` sends the standard ACP `session/cancel` notification and drops queued follow-ups so cancellation does not accidentally continue into another turn.

The stdio transport treats newline-delimited JSON framing independently from UI callbacks. stdout chunks are coalesced and drained in bounded batches, and each decoded frame is dispatched behind an error boundary. A broken notification/integration callback therefore reports an error without discarding later response frames from the same stdout chunk or permanently leaving the session in a prompting state.

## Transcript

The transcript is an unmodifiable Markdown buffer with a winbar that shows the active routing profile as `routing:<profile>`. The transcript and input windows explicitly clear the window-local `statuscolumn`, so the host editor's gutter UI cannot leak into the conversation surface. Native Markdown/Tree-sitter highlighting remains responsible for ordinary Markdown presentation; Phenix adds only semantic transcript highlights. Semantic headings use explicit, high-priority text extmarks so Markdown renderers cannot accidentally apply a heading style to a different transcript block. Pi's startup banner is omitted from the transcript; status belongs to a future status surface rather than conversation history.

Distinct blocks are used for user messages, assistant messages, thinking, plans/system messages, errors, and tool calls. Tool input/output is rendered as fenced Markdown. Thinking bodies and tool details use native manual folds and start closed, so normal Neovim fold commands (`zo`, `zc`, `za`) work directly. Rendering snapshots each entry's open/closed state before changing the transcript and reapplies it by stable entry identity, so streamed updates preserve folds.

Phenix-specific highlight groups are theme-linked rather than color-owned:

- `PhenixTranscriptUser`
- `PhenixTranscriptAssistant`
- `PhenixTranscriptThinking`
- `PhenixTranscriptTool`
- `PhenixTranscriptSystem`
- `PhenixTranscriptError`

## Configuration boundary

`require("phenix").setup(...)` configures only the Phenix frontend plugin. Its runtime entrypoint is intentionally small: `phenix.settings` owns merged defaults, `phenix.mappings` owns `<Plug>` and optional default mappings, `phenix.window` owns reusable local-window policy, and `phenix.markdown` is the optional Markview integration. Session, ACP, and UI modules load only when an action starts a session. Phenix orchestration authoring through `phenix.acp.*` is loaded from the selected Phenix configuration file and submitted to the conductor through `_phenix/config/apply`.

The frontend plugin does not own routing execution, workflows, downstream ACP sessions, generic pane/layout abstractions, or a separate editor framework. Those remain ACP/conductor concerns. Likewise, the rest of this repository's Lua runtime is distribution configuration unless it lives in an explicitly packaged local mechanism; configuration may consume plugin APIs, but reusable plugins must not reach back into distribution policy.
