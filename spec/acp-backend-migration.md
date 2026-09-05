# ACP backend migration

status: specification-only

depends on `matthis-k/phenix-conductor#489` and its stacked dependencies.

## Purpose

Replace the Neovim frontend's internal conductor protocol with the public ACP application path.

The first migration uses `phenix-acp` over stdio directly. Generated Lua bindings may replace the handwritten ACP client later without changing frontend session, projection, or UI semantics.

## Boundary

```text
phenix-nvim
   |
   | ACP JSON-RPC over stdio
   v
phenix-acp
   |
phenix-adapter-acp
   |
fixed Phenix application interface
   |
configured Phenix runtime
```

The editor owns UI state and local request correlation only. Phenix owns durable sessions, transcript semantics, routing, execution, tools, permissions, authentication, and persistence.

## Migration

Replace the old `lua/phenix/conductor.lua` internal-wire client with an ACP client that:

- spawns the packaged `phenix-acp` executable;
- performs ACP initialize and capability negotiation;
- creates, lists, resumes, renames, and closes sessions through public ACP behavior;
- submits prompts and consumes ordered session updates;
- renders tool-call and progress updates through the existing projection path;
- handles permission and elicitation callbacks through the supported ACP client mechanisms;
- cancels the active Phenix execution through ACP;
- uses negotiated `_phenix/...` extensions for Phenix-only session lineage, routing, callable, skill, execution-tree, provenance, and diagnostic behavior;
- feature-detects optional extensions instead of assuming their presence.

Do not translate the old internal command names into a private ACP extension. Map frontend behavior to standard ACP first, then use the public Phenix extensions defined by the application interface.

## Frontend preservation

Keep the existing Neovim UI ownership model unless ACP semantics require a small adapter change.

The migration should preserve:

- one transcript buffer per selected Phenix session;
- the persistent input buffer;
- session selector behavior;
- projection and transcript rendering;
- execution-tree presentation where the negotiated Phenix extension provides it;
- model/routing selection where the negotiated capabilities provide it;
- cancellation and authentication UI flows.

Protocol-specific values terminate in the backend client layer. Controller and rendering modules should consume frontend-native values rather than ACP JSON-RPC envelopes.

## Transport

Use Neovim's process APIs to spawn `phenix-acp` and carry ACP JSON-RPC on stdin/stdout.

Treat stdout as protocol-only. Surface stderr as diagnostics without parsing it as ACP.

The process lifetime must not define durable session lifetime. Restarting the child process should allow the frontend to list and resume runtime-owned sessions.

## Packaging

Consume the `phenix-acp` package from `phenix-conductor` through Nix.

Remove the old configured-Harness dependency once no runtime path uses it. The editor repository should not package or copy conductor-internal protocol definitions.

Do not vendor generated binding artifacts. A later generated Lua binding comes from the conductor repository as a packaged dependency.

## Generated binding follow-up

`matthis-k/phenix-conductor#491` defines the generated Lua binding path.

When that binding is available, `phenix-nvim` may replace its handwritten ACP framing with `require("phenix")`. Keep the controller-facing application behavior stable so that change is local to the backend client layer.

The direct ACP migration remains valuable as an integration regression and fallback test client even after the binding exists.

## Required regressions

Add coverage proving:

- Neovim starts `phenix-acp` and completes ACP initialization;
- the frontend creates a session, prompts, receives streamed text and tool updates, and cancels without the internal conductor wire;
- a process restart can list and resume a durable session;
- optional Phenix extensions are capability-gated;
- permission and elicitation callbacks return through ACP;
- stdout diagnostics cannot corrupt protocol parsing;
- the frontend does not persist a second transcript or session database;
- no Lua module constructs old `phenix-client` command envelopes;
- packaging starts with the conductor-provided `phenix-acp` executable.

## Completion

- [ ] the frontend communicates through public ACP only;
- [ ] `phenix-acp` is the packaged backend executable;
- [ ] standard ACP handles the behavior it represents;
- [ ] Phenix-only behavior uses negotiated public extensions;
- [ ] the old internal conductor client is removed;
- [ ] durable sessions survive backend process restart;
- [ ] controller and UI modules remain independent of ACP wire shapes;
- [ ] the backend layer can later be replaced by the generated Lua binding without a UI rewrite;
- [ ] exact-head CI passes.
