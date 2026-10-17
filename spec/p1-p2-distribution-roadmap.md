# Neovim distribution roadmap: P1 Basic to P2 Advanced

Status: planned. Owner: `phenix-nvim`.
Updated: 2026-10-16

This is the distribution rollout plan. The [standalone client's roadmap](https://github.com/matthis-k/phenix-ai.nvim/blob/main/spec/p1-p2-client-roadmap.md) owns SDK, Neovim UI, tools, local integrations and A2UI renderer milestones. The [runtime M1 roadmap](https://github.com/matthis-k/phenix-ai/blob/main/spec/m1-roadmap.md), [Advanced roadmap](https://github.com/matthis-k/phenix-ai/blob/main/spec/p2-advanced-agent-roadmap.md) and [runtime-management issue #891](https://github.com/matthis-k/phenix-ai/issues/891) own session, authority, configuration and agent behavior. This file owns only packaging, editor preferences and distribution acceptance.

## Fixed package and ownership model

`phenix-nvim -> phenix-ai.nvim -> phenix-ai`

- `phenix-ai` supplies the packaged Basic and Advanced products and their plugins. The runtime is authoritative for sessions, state, catalogs, tools, history, permissions and model selection.
- `phenix-ai.nvim` supplies the Lua client bridge, integration registry, default widgets/renderers, negotiated A2UI capability advertisement, chat controller and Neovim API. Other Neovim distributions can use it without this repository.
- `phenix-nvim` pins both dependencies, supplies theme, layout, keymaps, feature plugin configuration and optional local overrides. It imports only the standalone client's public Lua modules. It does not publish its own client capability handshake, protocol schema or runtime façade.

One source of truth for each interface. The distribution has no copy of the transcript reducer, session registry, model/provider catalog, transport or A2UI component definitions. Local registries are customization inputs to `phenix-ai.nvim`, not a second UI protocol.

## P1 rollout

| ID | Depends on | Distribution work | Observable acceptance |
| --- | --- | --- | --- |
| D0: remove outdated editor façade | [open PR #114](https://github.com/matthis-k/phenix-nvim/pull/114) | Finish replacing `phenix.frontend` dispatch and obsolete direct Phenix API shims with ordinary editor feature modules. Status bars read `phenix_nvim.status.get()`. Preserve functioning Git, LSP, picker, dashboard and keymaps. | All installed keymaps resolve to real modules; status does not import native runtime internals; packaged editor regression test passes. |
| D1: establish coherent P1 pins | Client N1-N3; accepted runtime Basic entry point | Change `phenix-ai.nvim` packaging to the M1 Basic artifact upstream, then pin that tested client and its matching `phenix-ai` revision here. Keep the client's upstream `phenix-ai` input following the distribution pin. Remove references to retired `phenix.so` or oldmain-only package names once upstream cutover is verified. | Nix evaluation/build finds actual package attributes, asserts matching pinned runtime, and launches packaged ACP Basic without legacy dependencies. |
| D2: make Basic the usable default | D0-D1 | Enable the standalone client's P1 backend, reuse existing chat window mappings and statusline, retain distribution appearance and keymaps. Do not recreate client session/model APIs to fill unavailable P1 controls. | Launch the configured editor, open chat, submit a turn, see ordered user/assistant/tool output, cancel, close chat and reopen it without losing runtime session history. |
| D3: end-to-end P1 regression | D2 | Extend `tests/distribution.lua` and the actual packaged Nix check. Run one fresh Basic session and one restart/resume with the same runtime/client pair; exercise a missing/denied capability and a failed launch. | A deterministic headless Neovim check uses the installed package, not source-only mocks. Ordinary Git/LSP completion, keymaps and status remain usable with the chat UI. |
| D4: management rollout **(P1/P2 product priority)** | Runtime #891 and client N4-N6 | Package and expose the standalone client's `:Phenix auth` and `:Phenix model` UX. Reuse runtime-advertised provider/connection/auth methods, zero/one/both method branching, secret-safe prompt/OAuth and usable dynamic/static model discovery. Only distribution-specific layout/keys belong here. Follow with other model/routing/authorization and follow-up menus; do not hard-code providers, models, URLs or secrets. | With installed `nvim-nix-live` and matching pinned runtime/client, authenticate by an offered API key or officially supported OAuth, select one of the actual usable model entries, submit a real turn, restart and verify selection; no unsafe fallback, secret leakage or forged client model catalog. |

**P1 distribution gate:** D0-D3 have green checks on one exact pinned client/runtime pair. D4 is an incremental user-facing parity gate, not grounds to reintroduce oldmain. When a runtime management operation is unavailable, leave it disabled with a clear explanation.

**P2 usability release priority:** D4 provider authentication and usable model selection are required before claiming that the packaged Advanced Neovim product is ready for interactive use. General A2UI and presentation enhancements remain additive. Auth and model semantics are owned solely by [runtime #891](https://github.com/matthis-k/phenix-ai/issues/891) and client N4, not this distribution.

## P2 rollout

| ID | Depends on | Distribution work | Observable acceptance |
| --- | --- | --- | --- |
| E1: composition selection | Runtime Advanced preset and client C1-C2 | Offer a clear Basic/Advanced product choice through supported package and runtime configuration. Do not fork the SDK or client per preset. | Both presets work through the same chat UI; Basic's package has no Advanced-only verification dependencies. |
| E2: local A2UI customization | Client C3-C5 and runtime P2-IO2/IO4 | Configure `phenix-ai.nvim`'s built-in A2UI renderer registry, optionally replace component implementations and add trusted local renderers. Apply distribution colors, keys and placement for text, buttons, inputs, checkboxes, cards and recursive containers. Client-owned defaults work without any distribution configuration. | Removing distribution overrides yields working client defaults. Adding/removing an override changes only local rendering and the client's advertised effective catalog; invalid UI actions never bypass runtime checks. |
| E3: workspace and agent views | Client C6; runtime P2-4 through P2-9 | Compose windows and navigation for code references, stale evidence, edit reviews/diffs, jobs, child-session tree, traces and usage. Reuse existing editor navigation and layout plugins. | The packaged Advanced verification product can edit/review, detach/attach a job, inspect a child and restore state after restart; Basic chat still works. |
| E4: multi-client and presentation regression | Runtime P2-IO1 through IO4; client C7 | Test one Neovim instance alongside an independent second frontend on the same runtime session. Cover catalog differences, reconnection, denied actions and renderer override changes. | Both clients see the same authorized session state with independent cursors. A text-only client is not sent unsupported form/SVG messages, and a removed override cannot leave live callbacks behind. |

### Rollout order and CI

1. Merge and verify the M1 runtime contract or package required by the next client slice.
2. Merge and verify `phenix-ai.nvim` against that exact runtime SHA, including its own protocol and Neovim tests.
3. Update this distribution's inputs together. Verify the package's embedded runtime revision equals the direct `phenix-ai` lock and that the client is the revision under test.
4. Run the distribution headless Neovim smoke test against the installed plugin and retain the CI link on the owning PR.

A documentation or editor-only change should not trigger a separate architecture-policing CI suite. Gate functional journeys at the owner boundary. Run full packaged integration after changes to package inputs or the public client. Keep tests deterministic and use independent protocol fixtures where they add coverage.

## Implementation handoff: distribution-only changes

This repository owns pins and editor packaging, not runtime contracts or the
standalone client's feature implementation. A coding task begins with the
upstream runtime/client SHAs already accepted by their owning tests. Work on
one runnable distribution change at a time. Check `flake.nix`,
`modules/package.nix`, `modules/outputs.nix` and
`tests/distribution.lua` before choosing a private Nix module layout.

| Packet | Change | Required packaged check |
| --- | --- | --- |
| **D1–D3: pinned Basic** | Update both `phenix-ai` and `phenix-ai-nvim` in `flake.lock` only after the upstream runtime and client are compatible. Keep the installed Basic ACP binary and standalone client selected in the existing modules. Remove dead legacy packaging only after the pinned replacement launches. | `nix flake check -L` and the existing headless distribution journey start the **installed** plugin, submit a prompt, cancel and resume an accepted session after a real process restart. A failed launch and unavailable capability report explicit errors. |
| **D4a: selected-model rollout** | Integrate accepted runtime ACP config-option support and client model picker via matching pins; expose existing `:Phenix model`, not a distribution-specific picker or provider catalog. | A real installed test switches among runtime-advertised model choices, checks the effective result and reconnect persistence. Disabled/denied model choices cannot be applied by a forged Lua action. |
| **D4b: authentication rollout** | Once #891 and N4 provide verified authorized credential flows, wire `:Phenix auth` through the same pinned package. Add only editor-specific mapping/theme or optional safe overrides. | Fake API-key/OAuth fixtures prove zero/one/two method UI, missing secret, expired/revoked profile and no credential in transcript/log/store. A separate manually authorized live-provider check is labelled as such, not presented as offline CI. |
| **E1: Advanced selection** | Expose the already-built `phenix-advanced` preset as a packaging/configuration choice without forking `phenix-ai.nvim` or changing Basic defaults. | Both presets use the same installed client and independent ACP product test; Basic package closure contains no verification-only Advanced plugin. |
| **E2: A2UI overrides** | Configure the standalone client's proven local registry only. Make theme/layout/component overrides optional so removing distribution config restores client defaults. | Advertised component catalog follows actual effective overrides. Removing an override invalidates its callback; malformed or unauthorized A2UI actions do not reach runtime effects. |
| **E3–E4: Advanced views** | Reuse the client views for code evidence, diff, job, child session and inspection; change distribution window composition/keymaps only. | Installed Advanced verification demonstrates edit/review, job detach/attach, child inspection and restart with a separate second client. Basic UX still passes after pin update. |

**Pinning procedure.** Verify runtime PR and exact-head tests; then verify
`phenix-ai.nvim` against that exact runtime; then regenerate both distribution
lock inputs together. Never hand-invent a `narHash` or merge a provisional
one. Test Nix evaluation/build and the installed Neovim product at the
same resulting commit. Record runtime SHA, client SHA, distribution SHA,
the specific commands and passing check links in the distribution PR.

Local package expressions, optional keybindings and visual styling remain
implementation choices. Missing runtime/client APIs are upstream blockers,
not an invitation to implement a parallel adapter here. Only update this
roadmap's acceptance state when the real installed-product gate passes.

## Current work and tracking

- Runtime P1 Basic: accepted. P2 is not accepted.
- `phenix-ai.nvim` [PR #48](https://github.com/matthis-k/phenix-ai.nvim/pull/48): P1 transport/UI migration is open and opt-in; its legacy default is temporary, not the target.
- `phenix-nvim` [PR #114](https://github.com/matthis-k/phenix-nvim/pull/114): editor-only façade removal merged and verified. This completed D0 without migrating the runtime package.
- `phenix-nvim` [PR #116](https://github.com/matthis-k/phenix-nvim/pull/116): optional Basic and HTTP-model P1 distribution variants now have installed editor, live-provider fixture, capability disclosure, and session-replay gates. These are not yet the default product.
- D0 is accepted. D1-D3 are under acceptance against a pinned runtime/client pair; D4 and E1-E4 remain unaccepted. Review the corresponding PR's exact-head CI before marking additional stages complete.

No separate feature questionnaire remains open. Implementation dependencies and deferred feature gates are recorded in the tables above.
