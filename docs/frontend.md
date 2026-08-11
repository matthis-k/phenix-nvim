# Phenix Neovim

`phenix-nvim` owns both the complete Phenix Neovim distribution and the independently consumable Phenix frontend plugin. The ACP/conductor repository owns protocol, routing, workflows, backend integration, and runtime state.

## Distribution boundary

The default `phenix-nvim` package is the full editor configuration ported from `matthis-k/nvim-flake`. The Lua editor configuration remains the source of truth: custom statusline, tabline, statuscolumn, options, keymaps, sessions, completion, LSP, Git integration, Snacks, Telescope, theme, and OpenCode integration live in the repository runtime tree.

Packaging is implemented with `nix-wrapper-modules`, not nixCats. Wrapper modules provide the Neovim executable, plugins, runtime tools, shared libraries, language providers, and the runtime path for the local configuration; they do not replace the Lua configuration with Nix options.

The Phenix frontend itself is a separate filtered package, exported as `phenix-nvim-plugin`. The default wrapped editor installs that package exactly once in addition to the ordinary editor configuration. Consumers that only want the Phenix ACP frontend can consume the plugin without inheriting this repository's complete editor configuration.

The packaged editor also supplies `phenix-conductor`, `pi-acp`, and the store-backed Phenix orchestration configuration required to initialize a real ACP session.

## Phenix UI surface

The plugin communicates with `phenix-conductor` over ACP stdio. It must not depend on plugin source exported from the ACP repository.

The frontend deliberately exposes one main action:

```vim
:PhenixToggle [cwd]
```

By default `<leader>pp` toggles the same action.

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

Steering uses the existing Phenix session-tree `Steer` operation. Follow-ups entered while a response is active are queued and submitted as the next ordinary ACP prompt.

## Transcript

The transcript is an unmodifiable Markdown buffer. Native Markdown/Tree-sitter highlighting remains responsible for ordinary Markdown presentation; Phenix adds only semantic transcript highlights.

Distinct blocks are used for user messages, assistant messages, thinking, plans/system messages, errors, and tool calls. Tool input/output is rendered as fenced Markdown. Thinking bodies and tool details use native manual folds and start closed, so normal Neovim fold commands (`zo`, `zc`, `za`) work directly.

Phenix-specific highlight groups are theme-linked rather than color-owned:

- `PhenixTranscriptUser`
- `PhenixTranscriptAssistant`
- `PhenixTranscriptThinking`
- `PhenixTranscriptTool`
- `PhenixTranscriptSystem`
- `PhenixTranscriptError`

## Configuration boundary

`require("phenix").setup(...)` configures only the Phenix frontend plugin. Phenix orchestration authoring through `phenix.acp.*` is loaded from the selected Phenix configuration file and submitted to the conductor through `_phenix/config/apply`.

The frontend plugin does not own routing execution, workflows, downstream ACP sessions, generic pane/layout abstractions, or a separate editor framework. Those remain ACP/conductor concerns; the rest of this repository's Lua files are ordinary Neovim distribution configuration rather than Phenix protocol machinery.
