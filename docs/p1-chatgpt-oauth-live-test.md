# P1 live ChatGPT OAuth acceptance (installed Neovim)

**Status:** Release gate, not proof of a completed external sign-in.

This tests the ChatGPT subscription path in addition to the OpenAI API-key
direct-entry and environment-variable-name paths documented in
`p1-openai-api-live-test.md`. Neither path can stand in for the other.

## Preflight

Use a coherent, checked `phenix-ai` → `phenix-ai.nvim` →
`phenix-nvim` revision set with the optional
`nvim-nix-chatgpt` package. The OAuth provider is an independent plugin
with a narrowly authorized per-account vault. It does not reuse API-key
storage identities or accept an API key as a ChatGPT plan credential.

```sh
export PHENIX_CREDENTIAL_FILE_CONSENT=1
export PHENIX_CREDENTIAL_FILE_DIRECTORY="${XDG_DATA_HOME:-$HOME/.local/share}/phenix/chatgpt-credentials"
install -d -m 0700 "$PHENIX_CREDENTIAL_FILE_DIRECTORY"
nix run .#nvim-nix-chatgpt
```

Have an eligible ChatGPT account with plan-use consent available. A signed
OpenID Connect identity without the granted
`chatgpt.tokens.use.direct` permission is **not** successful plan
authentication. OpenAI's official open-source SIWC integration is a public
OAuth client; do not ask for an API key, OAuth client secret or manually
copied token.

## Acceptance sequence

1. In Neovim, run `:Phenix auth`, select OpenAI → ChatGPT →
   **Sign in with ChatGPT**. The runtime starts a fresh PKCE/state/nonce
   challenge and opens the browser; q/Esc cancels the picker.
2. Complete the browser authorization and grant ChatGPT plan usage.
   Only the signed, issuer/audience/nonce-checked callback may complete
   `ProviderAuth`. Wrong state, wrong account, missing scope, expired
   challenge, or callback replay must fail without an authenticated status.
3. Run `:Phenix model` and select one actually available model from the
   signed-in account's `/v1/models` catalog. Model names are not assumed
   statically and hidden/ineligible models are not selectable.
4. Start a session (`:Phenix session new`), send a short prompt through
   `:Phenix send`, and verify a **real streamed** Responses API completion
   using the selected exact-account OAuth bearer token, with
   `store=false` and `stream=true`.
5. Restart Neovim, restore the session and verify the same account's
   authorization, selected model and source-backed history. The runtime must
   reject expired/revoked/missing tokens without falling back to API billing
   credentials or a preset model.
6. Check token renewal near expiry, durable replacement of rotating refresh
   tokens, two-process contention and explicit logout/remote revocation. A
   local sign-out may report that remote revocation was unconfirmed; it
   must not misrepresent that as a successful remote revoke.

## Security and negative cases

- The selected named account/profile, provider, connection, protocol and
  endpoint stay bound through discovery and execution. An unrelated API
  key or another ChatGPT account cannot satisfy this authorization.
- No access token, refresh token, ID token, verifier or callback code may
  appear in ACP replies, transcripts, Nix store outputs, client buffers,
  logs or journal.
- The initial first-time registration retains the *issued* OAuth client ID
  and stable host ID; `dynamic_agent_client` must not be exchanged as the
  active client ID.
- Cancelled/expired/replayed OAuth attempts never complete.
- A CI loopback fixture verifies protocol handling without claiming a
  paid-plan or live-account smoke. Complete this checklist only with actual
  eligible external-provider inference.

Upstream behavior is documented at
https://developers.openai.com/siwc/token-sharing-open-source .
Implementation tracking: phenix-ai#1074, runtime #1081 and #1094,
standalone Neovim client #111, distribution #165.
