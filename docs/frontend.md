# Phenix Neovim

`phenix-nvim` owns both the complete Phenix Neovim distribution and the independently consumable Phenix frontend plugin. The ACP/conductor repository owns protocol, routing, workflows, backend integration, and runtime state.

## Distribution boundary

The default `phenix-nvim` package is the full editor configuration ported from `matthis-k/nvim-flake`. It targets Neovim nightly so it can use the native `vim.pack` manager. The Lua editor configuration remains the source of truth, but each independent feature is a native optional package under `pack/phenix/opt`: `phenix-core` (shared utilities), `phenix-options`, `phenix-theme`, `phenix-bars-and-columns`, `phenix-session`, `phenix-snacks`, `phenix-keymaps`, `phenix-git`, `phenix-lsp`, `phenix-completion`, and `phenix-opencode`.

Packaging is implemented with `nix-wrapper-modules`, not nixCats. The wrapper supplies immutable third-party dependencies; the small distribution entrypoint uses `:packadd` in dependency order to activate local optional packages. No Lua plugin manager is used.

The Phenix frontend itself is a separate filtered package, exported as `phenix-nvim-plugin`. The default wrapped editor installs that package exactly once in addition to the ordinary editor configuration. Consumers that only want the Phenix ACP frontend can consume the plugin without inheriting this repository's complete editor configuration.

The packaged editor also supplies `phenix-conductor`, `pi-acp`, and the store-backed Phenix orchestration configuration required to initialize a real ACP session.

## Phenix UI surface

The plugin communicates with `phenix-conductor` over ACP stdio. It must not depend on plugin source exported from the ACP repository.

The frontend exposes actions through keymaps and `<Plug>` targets rather than user commands. Default normal-mode keymaps are grouped under `<leader>p`:

- `<leader>p`: toggle the UI;
- `<leader>pf`: open the UI fullscreen in the current tab;
- `<leader>pt`: open the UI fullscreen in a new tab;
- `<leader>pm`: toggle the prompt-only maximized view.

Integrations can map the corresponding normal-mode `<Plug>` targets instead of calling Lua: `<Plug>(phenix-toggle)`, `<Plug>(phenix-open-fullscreen)`, `<Plug>(phenix-open-fullscreen-tab)`, `<Plug>(phenix-maximize)`, and `<Plug>(phenix-shutdown)`.

`require("phenix").toggle({ ... })` accepts the same options as `setup`, with per-call values taking precedence. By default it opens a right-hand UI at 50% of the editor width and gives the prompt 25% of the editor height, clamped between 4 and 12 lines. `width` and `input_height` accept either an absolute number of cells/lines or a fraction from zero to one; `input_height_min` and `input_height_max` set the prompt bounds. The follow-up queue has matching `follow_up_height`, `follow_up_height_min`, and `follow_up_height_max` options. Set `fullscreen = true` to close other windows in the target tab before opening, or `tab = true` to open and switch to a new tab first.

The action opens one right-hand sidebar composed of exactly two Neovim windows:

- transcript;
- input.

Toggling the sidebar only hides or recreates those windows. It does not terminate the conductor process or discard the current transcript/input buffers.

## Input

The input is a normal editable `acwrite` buffer.

- Normal `<CR>` sends the prompt.
- Normal `<S-CR>` steers the active response.
- Normal `<M-CR>` queues a follow-up for the next turn.
- `:write` sends the prompt.
- Insert `<CR>` remains a normal newline.

The prompt window grows and shrinks to fit its wrapped visual lines within its configured bounds. Queued follow-ups appear in an automatically managed window between the transcript and prompt, using the same adaptive sizing behavior; it opens when work is queued and closes after the queue drains. `require("phenix").maximize()` toggles a prompt-only view; submitting by any send action restores the normal transcript-and-prompt view.

Steering uses the existing Phenix session-tree `Steer` operation. Follow-ups entered while a response is active are queued and submitted as the next ordinary ACP prompt.

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

The frontend plugin does not own routing execution, workflows, downstream ACP sessions, generic pane/layout abstractions, or a separate editor framework. Those remain ACP/conductor concerns; the rest of this repository's Lua files are ordinary Neovim distribution configuration rather than Phenix protocol machinery.
