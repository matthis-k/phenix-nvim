# P1 live authentication acceptance: OpenAI API

This is a manual **live-provider** test for the optional `nvim-nix-openai-api`
package. It complements the deterministic native HTTP fixture in
`phenix-ai/tests/acp-openai-api-key-product.py` and the installed standalone
client ACP lifecycle check. It is not evidence that a paid account has been tested.

## Preconditions

- Run the checked, coherent `phenix-ai` → `phenix-ai.nvim` →
  `phenix-nvim` source pins. A green feature-branch test does not establish
  that this distribution's `flake.lock` is up-to-date.
- Have a valid OpenAI **API billing** credential with permission to list
  available models and execute at least one Responses API model. ChatGPT Plus
  OAuth is a separate workflow and is not tested here.
- Use an explicit private per-user credential directory; never put the API
  key in Nix files, CLI arguments, a session transcript, or this runbook.

```sh
export PHENIX_CREDENTIAL_FILE_CONSENT=1
export PHENIX_CREDENTIAL_FILE_DIRECTORY="${XDG_DATA_HOME:-$HOME/.local/share}/phenix/credentials"
install -d -m 0700 "$PHENIX_CREDENTIAL_FILE_DIRECTORY"

# Only for the environment-variable-name source path:
export OPENAI_API_KEY='your-own-private-api-key'

nix run .#nvim-nix-openai-api
```

If testing direct key entry instead, leave `OPENAI_API_KEY` unset and
enter the key into the private prompt. No key is needed to test the picker
or cancellation path.

## Native Neovim journey

1. Run `:Phenix auth`, choose OpenAI → API and **API key**.
   Choose either **Enter API key** or **Read from environment variable**.
   For the second choice provide only `OPENAI_API_KEY`, not its value.
2. Confirm the resulting status is **provider verified**, not merely stored.
   A wrong/revoked key must remain unavailable.
3. Run `:Phenix model`; select a model actually returned as usable for the
   named authenticated account. Do not assume a specific model entitlement.
4. Start a session with `:Phenix session new`, enter a short prompt in the
   compose buffer, then `:Phenix send`. Verify streamed assistant content
   and one completed turn; no preset/other-account fallback is allowed.
5. Exit Neovim, start the same package again, and load the session.
   Verify selected-account consistency and that the credential still resolves.
6. Run `:Phenix auth revoke openai api personal`. A subsequent attempt to
   use the revoked selected account must fail closed. If using an environment
   source, revoke removes the **stored variable-name binding**, not the
   variable from the parent shell.

## Failure and security checks

- Wrong profile, missing env variable, invalid key, or inaccessible
  credential store must not silently select an unrelated account.
- On revocation or restart, do not fall back to legacy default HTTP credentials.
- Ensure no secret/token appears in the transcript, notifications, logs,
  persisted model selection or a Nix store path.
- The documented live test is accepted only after observing an actual response
  from the selected provider. Mock-model, metadata-only and UI-only tests do
  not count as live external-provider execution.

Track implementation in runtime issue #891, OAuth issue #1074,
runtime bundle PR #1083 and standalone client #114.
