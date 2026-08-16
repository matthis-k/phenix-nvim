# Phenix Neovim

`phenix-nvim` is the Neovim distribution and the Neovim-facing frontend for the Phenix conductor. The conductor owns runtime semantics: sessions, executions, routing, model/backend catalogs, authentication selection, tools, workflows, persistence, and lifecycle. Neovim owns editor interaction and semantic rendering.

The frontend protocol boundary is Phenix-owned NDJSON. ACP is not a frontend API and is not exposed through `phenix-nvim`; backend-specific ACP integration remains below the conductor backend abstraction.

## Feature collection

The distribution keeps user-facing responsibilities independently packageable where that creates a coherent API and lifecycle. Shared `vim.opt` policy and final distribution keymaps remain distribution configuration.

The current collection includes:

- `phenix-ui`: implementation-agnostic frontend utilities plus the shared typed Phenix API/config/state runtime;
- the native agent frontend: conductor transport, typed client, state store, semantic projection, session controller, and transcript/input UI;
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

The default wrapped editor composes these features. The agent frontend is exported as `phenix-frontend-plugin`; the other feature plugins retain their own flake packages.

## Shared typed frontend runtime

`phenix-ui` initializes one global facade:

```lua
---@class PhenixGlobal
---@field config PhenixConfig
---@field state PhenixState
---@field api PhenixApi
_G.Phenix = Phenix
```

Every feature extends the same three namespaces under one key:

```lua
Phenix.config.git
Phenix.api.git
Phenix.state.git

Phenix.config.agent
Phenix.api.agent
Phenix.state.agent
```

The native agent frontend registers under `agent`, never `acp`:

```lua
local agent = Phenix.api.agent
agent.setup({})
agent.toggle()
local live = Phenix.state.agent.session
```

`Phenix.require_api(name)` is available for dynamic dispatch that should fail immediately when a feature is unavailable. Ordinary integrations should prefer the typed direct index.

Feature plugins register public facades with `require("phenix.frontend").register_api()`. Registration also creates the matching config and state namespaces. The registry is shared frontend infrastructure; it is not a protocol escape hatch.

`phenix.frontend.window` contains shared window helpers, including the line builder and all-or-none UI groups. A group owns every related window and buffer: externally closing one member closes the remaining windows and deletes the remaining buffers. Explicit unmounting hides the group without stopping the conductor session.

## Dependency direction

```text
Neovim distribution policy
        |
        v
feature plugins -----> phenix-ui
        |
        +-----> third-party editor integrations where needed

native agent frontend -----> phenix-ui
        |
        +-----> phenix-conductor over Phenix NDJSON stdio
                         |
                         +-----> backend adapters, including ACP where applicable
```

The important boundary is one-way: Neovim does not construct backend sessions, route models, execute workflows, or call ACP methods. It sends normalized conductor commands and projects normalized conductor state/events.

## Native conductor client

`lua/phenix/transport.lua` owns the process and newline-delimited JSON framing. `lua/phenix/conductor.lua` is the typed request client. The public command set used by the frontend is deliberately narrow:

- initialize from an optional event-sequence cursor;
- create, fork, rename, and select sessions;
- set a typed fixed or routed execution target;
- submit input;
- cancel an execution;
- refresh backend catalogs;
- select a typed authentication method.

There is no arbitrary request method and no ACP-shaped fallback.

The wrapped editor injects the paired `phenix-conductor` binary through `PHENIX_CONDUCTOR_COMMAND`. Standalone configuration may provide `conductor_command`. `conductor_cwd_arg = false` is available for fixtures or conductors that do not take the wrapper's `--cwd` argument.

Protocol JSON object `null` values are normalized at the transport boundary to Lua `nil`, so optional fields such as parent IDs and names have one representation throughout the frontend.

## Runtime state and synchronization

The conductor is the runtime authority. The frontend does not infer execution lifecycle from UI activity.

`lua/phenix/store.lua` retains normalized session/execution snapshots and the last accepted event sequence. `lua/phenix/projection.lua` converts ordered conductor events into semantic transcript blocks. `lua/phenix/controller.lua` coordinates the typed client, store, projection, and UI-facing state.

Synchronization is sequence-based:

1. initial startup requests `initialize` and installs the conductor snapshot plus complete event history;
2. command reconciliation uses `initialize(after_sequence)` as a cursor barrier;
3. live events received while reconciliation is active are buffered;
4. returned event history must be exactly contiguous through the snapshot's `last_event_sequence`;
5. the snapshot is installed, returned history updates the semantic projection, then only buffered events beyond the covered sequence are replayed;
6. gaps, stale snapshots, or malformed histories trigger bounded full resynchronization instead of accepting ambiguous state.

State-changing frontend commands are serialized while a mutation or reconciliation barrier is unresolved. This prevents overlapping submits, cancellation, or target changes from racing the local projection after the conductor has already accepted a mutation.

Session activity and cancellation select the active **root** execution. Child executions remain visible in the semantic event stream but do not replace the root execution for session-level activity decisions.

## Agent facade

The plugin exposes the native frontend as `Phenix.api.agent`. The current facade includes:

- `setup()`;
- `toggle()`;
- `maximize()`;
- `cancel()`;
- `restore()` / `select_transcript()`;
- `select_model()`;
- `authenticate()`;
- `current()`;
- `shutdown()`.

`setup()` only configures the frontend. Distribution mappings target public `<Plug>` actions rather than implementation modules.

Model selection is typed. The picker consumes conductor backend/model catalogs and sends `set_session_target` with a concrete fixed target. A configured routed target remains a typed conductor target; Neovim does not perform routing itself.

Authentication selection is also typed. The picker consumes conductor authentication descriptors and sends the selected backend/method ID. Provider credentials and provider-specific authentication mechanics remain outside the frontend.

## Input, follow-ups, and unsupported capabilities

The input is a normal editable `acwrite` buffer:

- Normal `<CR>` sends;
- Normal `<M-CR>` queues a follow-up while the root execution is active;
- `:write` sends;
- Insert `<CR>` remains a newline.

The UI still exposes the existing steering gesture, but steering is intentionally unavailable until the normalized conductor protocol has steering semantics. It reports that limitation rather than falling back to ACP. The same rule applies to workflow invocation, delegation, and image submission.

Queued follow-ups are frontend-local pending input. They are displayed in dedicated editable windows and are submitted through the ordinary normalized `submit` command once the current root execution settles. Cancellation clears queued follow-ups.

## Transcript and UI lifecycle

The transcript is an unmodifiable Markdown buffer. Markview is used when available. User, assistant, reasoning, error, child-execution, and tool-call blocks remain semantically distinct.

Reasoning and tool details use native folds with custom previews. Tool arguments remain structured until rendering so multiline values become multiline Markdown/code blocks instead of flattened text.

Streaming/render updates preserve editor intent:

- when the cursor is on the last transcript line, it follows the new last line and keeps the tail visible;
- otherwise the cursor line and viewport are retained;
- expanded semantic folds remain expanded across rerenders;
- render bursts are coalesced and Markview reparses are debounced.

The transcript and prompt are one UI group. Closing either externally closes the whole group but leaves the conductor process/session alive. Hiding and reopening the UI likewise preserves the live session and transcript. Fullscreen/tab mounting and prompt maximization are UI-only operations and do not alter runtime ownership.

## Test boundary

Frontend CI uses a deterministic native-conductor fixture rather than an ACP frontend fixture. The functional smoke suite covers both protocol/state invariants and protocol-independent UI invariants, including:

- ordered snapshot/event reconciliation and duplicate suppression;
- serialized mutations and root/child execution selection;
- model/authentication/session commands;
- semantic transcript and multiline tool rendering;
- Markview integration and semantic folds;
- cursor/viewport tail-follow rules and render coalescing;
- follow-up queue editing/cancellation;
- grouped-window all-or-none behavior;
- persistent transport across UI hide/close;
- tab/fullscreen/maximize behavior;
- packaged native-conductor startup.

The migration should remove obsolete protocol tests, not frontend behavior tests that remain valid under the native conductor architecture.
