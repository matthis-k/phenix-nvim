# Phenix authentication UX acceptance

This is a **user-run, installed Neovim** acceptance test of the currently
shipped OpenAI API-key provider, plus a separate deterministic OAuth UI test.
It does not assert working ChatGPT-plan OAuth, nor does API billing become a
subscription benefit.

## 1. Real OpenAI API-key UX (requires your own key)

On the machine with your graphical Neovim/browser environment:

```sh
mkdir -p "$HOME/.local/state/phenix/openai-api-credentials"
chmod 700 "$HOME/.local/state/phenix/openai-api-credentials"
export PHENIX_CREDENTIAL_FILE_DIRECTORY="$HOME/.local/state/phenix/openai-api-credentials"
export PHENIX_CREDENTIAL_FILE_CONSENT=1
nix run 'github:matthis-k/phenix-nvim#nvim-nix-openai-api'
```

This explicitly selects the local, protected file-backed credential store.
It is **not encrypted at rest**. Never put an OpenAI API key in a Nix flake,
command-line argument, Git commit or ChatGPT conversation. Do not export the
key in the shell for this preset: use Neovim's masked prompt.

Inside Neovim:

1. Run `:Phenix auth`. The installed profile must be exactly
   `openai/api/personal`, not an arbitrary new account.
2. Enter a valid **OpenAI API billing** key via the masked prompt. Credential
   storage alone must not produce a successful login; Phenix must verify it
   with `https://api.openai.com/v1/models`.
3. Run `:Phenix new` to create the active Basic session.
4. Run `:Phenix model`, choose a model offered by the currently verified
   account, and confirm the model selection. The picker needs an active
   session; it must not create one implicitly.
5. Type a short prompt in the compose buffer and send with Enter in normal
   mode. Expect a streamed assistant response from the selected HTTP Model.
   A discovered model may still be denied for quota/billing; this is a
   provider error, not proof of a broken authentication contract.
6. Quit and reopen with the same environment and preset. The protected
   credential and session record should remain available; auth status and
   model eligibility must be **reverified**, not assumed from the local file.
7. Run `:Phenix auth revoke openai api personal` and explicitly confirm.
   A subsequent selected-model request and a reload after restart must not
   reuse the revoked credential.

### Negative cases

- Enter an invalid key. It may be stored, but the provider status must be
  unavailable. The UI must not announce a verified account or select a
  native credentialed model based only on storage success.
- Try choosing an unadmitted profile. The launcher must refuse it without
  touching another account's credential resource.
- Start the default `nvim-nix` instead. `:Phenix providers` may show
  registered authentication methods, but `:Phenix auth` must **not** ask for
  a key or launch a browser: the catalog-only composition has no login grant.

## 2. Deterministic Neovim OAuth UX regression

```sh
nix build 'github:matthis-k/phenix-ai.nvim#checks.x86_64-linux.ui-fast'
```

The merged `p1_oauth_ux_journey.lua` test drives `:Phenix auth` using a
scoped runtime mock. It verifies browser challenge, pending/repeated/reissued
challenge, completed provider status, expiry, unsafe URL refusal, and that Lua
never acquires an OAuth access/refresh token. It makes no external login
request and does **not** establish ChatGPT plan entitlement.

## 3. ChatGPT-plan OAuth: explicitly not yet accepted

The actual `openai/chatgpt` sign-in cannot pass its live acceptance gate
until [phenix-ai #1074](https://github.com/matthis-k/phenix-ai/issues/1074)
implements provider-owned code exchange and OIDC verification, account
identity and granted-scope checks, secure credential persistence/refresh/
revoke, model discovery and selected inference. Do not treat the presence
of `OAuthAuthorizationCode` in `:Phenix providers` as a usable login.
