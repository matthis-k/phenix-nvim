# Phenix Neovim Frontend Redesign v1

Status: proposed normative frontend specification.

This specification defines `phenix.nvim` as a Neovim frontend for the Phenix conductor. Runtime semantics are defined canonically in `phenix-agent-harness/spec/runtime-redesign-v1.md`; this document only specifies frontend responsibilities and conformance.

## 1. Goal

`phenix.nvim` is a thin, Neovim-native projection/controller for conductor state.

Target shape:

```text
Neovim
  |
  +-- phenix.nvim
      |
      +-- raw local transport
      +-- typed conductor client
      +-- snapshot/event state store
      +-- semantic transcript projection
      +-- Neovim UI/layout/input integration
  |
  v
phenix-conductor
```

`phenix.nvim` MUST remain useful as a rich frontend without becoming an agent runtime.

## 2. Explicit ownership boundary

`phenix.nvim` MUST own:

- buffers, windows, extmarks, folds, highlights, virtual text;
- layout and UI groups;
- input editing and editor integration;
- keyboard/mouse mappings;
- frontend-local selection overlays;
- viewport/cursor preservation;
- markdown/image/tool/reasoning presentation;
- projection of conductor snapshots/events into renderable frontend state;
- local presentation preferences.

`phenix.nvim` MUST NOT own:

- routing logic;
- workflow scheduling;
- agent delegation semantics;
- callable/tool policy;
- backend sessions;
- ACP sessions or ACP method semantics;
- provider authentication semantics;
- persistent Phenix session truth;
- configuration parsing/compilation;
- model selection precedence;
- execution lifecycle truth.

## 3. Layering

The frontend SHOULD be decomposed into these layers:

```text
transport.lua
  process/socket lifecycle + framed messages only

conductor_client.lua
  typed Phenix frontend protocol

store.lua
  snapshot + ordered event reducer

projection.lua
  semantic frontend view model/transcript blocks

controller.lua
  user intentions -> typed conductor commands

ui/*
  Neovim windows/buffers/rendering/interactions
```

A large `session.lua` object that simultaneously owns protocol, state, ACP extensions, configuration, backend auth, rendering, and user actions is not an acceptable final architecture.

## 4. Raw transport

The raw transport MUST be protocol-neutral.

It MAY support stdio initially and SHOULD later support the persistent conductor IPC transport.

It owns only:

- process/socket start/stop/reconnect;
- byte/string framing;
- decoding/encoding transport payloads;
- bounded stdout/input draining or equivalent backpressure;
- transport error/exit notification.

It MUST NOT own:

- request IDs;
- conductor command names;
- JSON-RPC semantics;
- ACP handshake;
- permission requests;
- session IDs;
- retries with application meaning.

If newline-delimited JSON is used, `transport` sends/receives whole decoded message objects and has no knowledge of their schema.

## 5. Conductor client

The conductor client MUST speak only the Phenix frontend protocol.

It owns:

- request/reply correlation;
- protocol initialization/version negotiation;
- typed command constructors;
- structured error decoding;
- unsolicited event delivery;
- snapshot/reconnect requests;
- event cursor tracking sufficient to request missed events.

It MUST NOT expose a public arbitrary `request(method, params)` API. Public frontend/integration APIs should be semantic operations such as:

```text
create_session
fork_session
set_target
submit
cancel
start_workflow
select/authenticate backend/model through typed APIs
subscribe to state/events
```

Backend or ACP method strings MUST NOT appear in normal frontend code.

## 6. State store

The frontend MUST maintain a local projection store derived from:

```text
conductor snapshot + ordered server events
```

The store is a cache/projection, never authoritative runtime state.

Requirements:

- applying an event MUST be deterministic;
- events MUST be applied in sequence order;
- a sequence gap MUST trigger resynchronization rather than guessing;
- reconnect MUST replace/reconcile from a conductor snapshot and continue from its cursor;
- execution state MUST be derived from conductor lifecycle events, not local `prompting`/`cancelling` booleans;
- session tree/lineage MUST be derived from conductor session summaries;
- model/routing display MUST be derived from the conductor `ExecutionTarget`/resolved execution data.

Frontend-only state, such as which fold is open, MAY live separately and MUST NOT be sent back as runtime state.

## 7. Transcript projection

The transcript MUST project semantic execution events while preserving causal order.

Minimum semantic block model:

```text
UserMessage
AssistantMarkdown
Reasoning
ToolCall
ToolResult
ChildExecution
Error
Image/Artifact when supported
```

Rules:

- reasoning and tool calls MUST remain interleaved exactly as emitted;
- tool arguments/results MUST support multiline rendering;
- agent/workflow children MAY be represented as expandable blocks but their position is determined by ordered events;
- no regrouping into "all thinking", "all tools", then "answer";
- rendering MUST NOT depend on raw ACP notifications.

## 8. Rendering

Rendering SHOULD use existing Neovim/plugin primitives at the highest suitable abstraction.

Required principles:

- use `markview.nvim` for markdown rendering where it fits instead of implementing a competing markdown engine;
- use Phenix line-builder APIs for status/winbar-like structured lines instead of direct ad-hoc mutation where those APIs exist;
- use extmarks/folds/virtual text for semantic overlays rather than rewriting unrelated buffer content;
- frontend rendering MUST be incremental enough not to peg a CPU core during streaming.

Tool/reasoning fold previews SHOULD be frontend-specific semantic summaries, not backend strings.

## 9. Cursor and viewport invariants

Rendering MUST preserve user navigation.

For transcript updates:

- if the cursor was on the last transcript line before rendering, it MUST remain on the last line afterward;
- otherwise the same logical line/cursor position SHOULD be retained as far as possible;
- if the cursor was on the last line and the viewport followed the tail, the last line MUST remain at the bottom of the viewport;
- otherwise the viewport SHOULD remain stable;
- markdown re-rendering MUST NOT force the cursor to the top/bottom;
- normal Vim motions (`j/k`, scrolling) MUST remain usable while output exists.

## 10. UI groups

One visible Phenix interaction is an atomic UI group.

Conceptually:

```text
PhenixUIGroup
├── transcript buffer/window
├── input buffer/window
├── info/sidebar window(s)
└── group-owned local resources
```

Operations MUST target the group where lifecycle is coupled:

```text
open
close
destroy
focus_input
resize
restore
```

If a required member of the group is intentionally closed/deleted, the group MUST cleanly close/destroy all coupled members rather than leave orphan buffers/windows.

The conductor session itself MUST NOT be destroyed merely because the Neovim UI group closes.

## 11. Input model

Input is a frontend concern; execution meaning is a conductor concern.

The frontend MAY provide:

- simple inline editor mode;
- embedded `$EDITOR`/buffer editing mode;
- external editor mode;
- slash-command completion;
- image attachment selection;
- follow-up queue presentation.

After parsing a frontend-local UI command, runtime operations MUST map to typed conductor commands.

The frontend MUST NOT infer workflow/routing/backend behavior from command strings after that mapping.

## 12. Model/routing selection

The UI MUST display exactly one semantic target state:

```text
Fixed: backend/provider/model + inference mode
```

or

```text
Routed: routing/profile
```

There MUST NOT be independent model and routing states with precedence/fallback behavior.

Selection UIs obtain available models/routing profiles from conductor state/catalog and send one typed target mutation.

For a fixed target, workflow/agent descendants use the conductor-defined fixed-target inheritance rule. The frontend MUST NOT override that rule.

## 13. Workflows and delegation

Workflow/agent catalogs come from conductor state.

`phenix.nvim` MAY provide ergonomic selectors, commands, status, and tree views, but MUST only submit typed callable/workflow intentions.

It MUST NOT:

- execute workflow steps;
- construct ad-hoc child sessions as workflow semantics;
- decide model routes for workflow roles;
- call `_phenix/*` or ACP extension methods as the permanent integration API.

Execution tree rendering comes from conductor execution state/events.

## 14. Tool and permission UI

Tool semantics and authorization belong to the conductor.

The frontend MAY render:

- tool call start/arguments/progress/result;
- a conductor-issued permission request;
- user selection/approval response;
- terminal UI needed for an explicitly described auth/tool interaction.

The frontend MUST NOT decide whether a tool is legal based on its own allowlists or execute conductor tools locally because of an adapter implementation detail.

Current development policy may auto-approve conductor-permitted tools; that policy remains outside `phenix.nvim`.

## 15. Authentication UI

Authentication actions are described by the conductor/backend abstraction.

The frontend MAY host an interactive terminal/window when requested, but MUST NOT contain provider-specific login flow semantics such as "Pi requires command X" or "ACP backend Y uses method Z".

Provider-specific mechanics MUST be opaque to `phenix.nvim` except for user-facing descriptions/actions supplied through the typed protocol.

## 16. Configuration

`phenix.nvim` MAY discover a configured Phenix config path as part of launch UX and pass it to the conductor.

It MUST NOT:

- parse/compile workflow definitions;
- build routing tables;
- reconstruct conductor callable catalogs from Lua source;
- own configuration revision semantics.

The frontend displays the immutable active/pinned configuration metadata returned by the conductor.

## 17. Persistence and reconnect

Closing or crashing Neovim MUST NOT imply loss of the Phenix session.

Target behavior:

```text
nvim exits
conductor remains authoritative/persistent
nvim restarts
client reconnects
snapshot + events reconstruct UI
```

The frontend MUST tolerate conductor reconnect/resnapshot. Frontend-local view state may be lost unless explicitly persisted, but runtime/session/execution state must reconstruct from conductor data.

## 18. Public Lua API

The final public API SHOULD expose semantic frontend operations and subscriptions, for example:

```lua
phenix.open(...)
phenix.current()

session:submit(...)
session:cancel(...)
session:set_target(...)
session:start_workflow(...)
session:fork(...)
session:state()
session:subscribe(...)
```

Low-level backend/ACP RPC is not a supported public API.

Integration plugins SHOULD use Phenix frontend abstractions (UI group, line builder, semantic APIs) where available instead of bypassing them with direct raw Neovim primitives for the same responsibility.

## 19. Failure behavior

Frontend failures MUST be visible but non-destructive to conductor state where possible.

Examples:

- malformed/unknown server event -> show diagnostic and resync;
- sequence gap -> resnapshot;
- conductor transport disconnect -> mark UI disconnected and reconnect/allow reconnect;
- execution failure -> render conductor-provided execution error in transcript/status;
- frontend renderer error -> preserve raw projected state and report locally; do not mutate conductor session to compensate.

Backend-native errors MUST arrive already normalized by the conductor.

## 20. Testing requirements

Required tests:

1. raw transport framing without protocol semantics;
2. conductor-client request/reply/event correlation;
3. reducer determinism from snapshot + event sequences;
4. sequence-gap/reconnect behavior;
5. transcript ordering with reasoning -> tool -> reasoning -> content;
6. multiline tool rendering;
7. cursor-last-line invariant;
8. non-tail cursor/viewport preservation;
9. UI-group all-or-none lifecycle;
10. fixed vs routed status projection;
11. close/reopen UI without semantic session destruction;
12. smoke test against a mock/real `phenix-conductor` frontend server without ACP-specific expectations.

Tests MUST target frontend behavior/public semantic interfaces, not deleted ACP extension compatibility.

## 21. Performance requirements

- no polling loop for rendering or backend/session status;
- streaming updates are event-driven;
- stdout/event draining MUST be bounded per scheduled UI turn to avoid starving Neovim;
- only affected transcript regions SHOULD be recomputed when practical;
- rendering while idle MUST consume effectively no CPU;
- transcript size growth MUST not cause full-buffer reparsing on every tiny delta when avoidable.

## 22. Migration sequence

### N0 — specification only

Merge this document before frontend runtime redesign PRs.

### N1 — transport purge

Create/retain a raw protocol-neutral transport. Quarantine the current JSON-RPC/ACP client as an explicitly temporary compatibility module.

Acceptance: raw transport contains no JSON-RPC/ACP/session semantics.

### N2 — native conductor client

Add typed Phenix protocol client on the raw transport without migrating UI/session state yet.

### N3 — snapshot/event store

Add conductor snapshot/event reducer and semantic projection types. Tests prove deterministic reconstruction and causal transcript order.

### N4 — controller/session migration

Replace ACP-shaped session application logic with typed conductor commands + projected state. Split the current all-in-one session responsibilities.

Acceptance: prompt/cancel/session target/workflow actions operate without ACP method strings in controller/UI code.

### N5 — rendering migration

Drive transcript/status/info panes entirely from semantic projection. Implement folding, markview integration, cursor/viewport invariants, and execution-tree views.

### N6 — auth/catalog/workflow UI parity

Restore product UX on normalized conductor APIs.

### N7 — delete ACP frontend compatibility

Delete `phenix.acp`, all `_phenix/*` calls, ACP session/config option logic, and legacy frontend tests.

### N8 — persistent reconnect

Connect to independently persistent conductor IPC and validate frontend restart/resume behavior.

## 23. Definition of frontend completion

The frontend redesign is complete when:

- no ACP/JSON-RPC concept exists above the temporary/raw transport boundary;
- `phenix.nvim` uses one typed conductor client;
- UI state is reconstructible from conductor snapshot + events;
- transcript order exactly follows canonical execution events;
- workflows/routing/tools/auth are displayed/controlled but not implemented by the frontend;
- coupled windows/buffers behave as one UI group;
- cursor/viewport behavior remains Vim-like during streaming;
- closing Neovim does not semantically destroy sessions;
- idle frontend/runtime integration does not peg a CPU core;
- obsolete compatibility modules and tests are deleted.
