# ProviderRuntime preview: installed Neovim acceptance

This is the opt-in Neovim distribution pinned to the concrete provider-runtime
migration in `phenix-ai` #1136 (with the canonical contract from #1135).
It is not a release or proof that `ProviderRuntime::complete` is connected.

## Start the test package

```sh
nix run 'github:matthis-k/phenix-nvim?ref=feat/provider-runtime-preview-20261024#nvim-nix'
```

For a local checkout of this branch, `nix run .#nvim-nix` uses the same
cryptographically locked upstream revision. The client follows that exact
`phenix-ai` input. No credential must be placed in `flake.nix` or the
shell: the P1 launcher initializes the private credential directory itself.

## Exercise the already supported P1 ACP surface

1. Run `:Phenix auth` and confirm that OpenAI offers the API-key and
   ChatGPT OAuth connections. Cancel once with Esc/q and confirm there is no
   newly authenticated account.
2. Repeat the API-key route. Choose masked direct input or a named environment
   variable. A stored key is not yet verified: only real `/models` validation
   may mark the selected account authenticated.
3. Run `:Phenix new`, then `:Phenix model`. Select an eligible model from
   the actual account-scoped catalog, not an arbitrary model ID.
4. Send a small prompt, test `:Phenix cancel`, then reopen the editor and
   confirm durable session replay. Model completion here still uses the
   existing selected HTTP `Model::complete` path, *not* the new
   `ProviderRuntime::complete` implementation.
5. If using ChatGPT OAuth, run `:Phenix auth` and select the browser login
   method; exercise cancellation and an authorized callback. This may require
   an eligible ChatGPT account. Presence of an OAuth connection is not proof
   of inference entitlement.
6. Optionally revoke an account through `:Phenix auth revoke` and confirm
   subsequent requests cannot reuse it. Never include keys, tokens or browser
   callback URLs in bug reports.

## Build/verification gates

```sh
nix build 'github:matthis-k/phenix-nvim?ref=feat/provider-runtime-preview-20261024#checks.x86_64-linux.default-p1-auth-frontend-wiring'
```

GitHub [PR #172](https://github.com/matthis-k/phenix-nvim/pull/172)
runs the full packaged Neovim headless checks, including a clean
`:Phenix auth` provider picker, Basic compatibility, and the combined P1
authentication composition. The locked `phenix-ai` rev is sourced directly
from PR #1136, using its verified NAR hash, never a mutable branch at build
time.

## Known boundary

The canonical native `ProviderRuntime` API now has three operations,
`authenticate`, `models` and `complete`, and real API-key/OAuth plugins
provide the first two by delegating to their existing private mechanisms.
Neovim communicates over ACP, which currently uses the legacy provider
management commands. This preview tests that those existing commands
continue working with the migrated runtime. It **does not yet expose a new
Neovim command that directly invokes the canonical M1 contract**.

Until the selected streaming adapter is migrated, the canonical
`ProviderRuntime::complete` intentionally refuses invocation rather than
silently making a synchronous request or using an unauthorized account.
