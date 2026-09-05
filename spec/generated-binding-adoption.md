# Generated binding adoption

status: specification-only

depends on `matthis-k/phenix-nvim#49` and `matthis-k/phenix-conductor#491`.

## Purpose

Replace the handwritten Lua ACP client with the generated `phenix-binding-lua` package after the public ACP backend migration is proven.

This is a maintenance follow-up. It must not change frontend application semantics.

## Boundary

```text
phenix-nvim controller/UI
        |
        | Lua application API
        v
require("phenix")
  generated Lua binding
        |
phenix-client-acp
        |
ACP
        v
Phenix
```

The generated binding and the direct ACP client both implement the fixed Phenix application interface. Switching clients should remain local to the backend integration module.

## Migration

- add the packaged generated Lua module to the Neovim runtime;
- replace handwritten ACP request, response, event, capability, and extension definitions with generated binding calls;
- keep Neovim event-loop scheduling in the frontend integration layer;
- preserve existing controller-native session and projection values;
- remove duplicated ACP framing and `_phenix/...` schema definitions once no test requires them;
- retain at least one direct stdio integration regression outside the production frontend path so `phenix-acp` remains independently tested.

## Completion

- [ ] `require("phenix")` loads the conductor-provided generated binding;
- [ ] production frontend code no longer implements ACP framing or Phenix extension schemas;
- [ ] generated capability and operation definitions come from the fixed application descriptor;
- [ ] controller and rendering behavior remains unchanged;
- [ ] Neovim event-loop integration remains non-blocking;
- [ ] direct ACP stdio remains covered by an integration regression;
- [ ] exact-head CI passes.
