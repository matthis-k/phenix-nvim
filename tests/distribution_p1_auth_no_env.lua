-- Real installed :Phenix auth must reach provider selection without
-- PHENIX_CREDENTIAL_FILE_DIRECTORY or PHENIX_CREDENTIAL_FILE_CONSENT.
local runtime = require("phenix_nvim.runtime")
local config = require("phenix_nvim.config").get()
assert(config.backend == "p1", "not installed P1 backend")
assert(type(config.command) == "string"
  and config.command:match("/bin/phenix%-basic%-p1%-auth%-acp$"))
assert(runtime.p1_active(), "P1 runtime not active")
assert(vim.fn.exists(":Phenix") == 2, "auth command absent")

local selected, failures = nil, {}
local original_select = vim.ui.select
local util = require("phenix_nvim.util")
local original_notify = util.notify
vim.ui.select = function(items, opts, callback)
  assert(opts.prompt == "Phenix provider (declared, not authenticated)",
    "unexpected authentication picker: " .. tostring(opts.prompt))
  local found
  for _, item in ipairs(items) do
    if item.id == "openai" then found = item end
  end
  assert(found and #found.connections >= 2,
    "missing OpenAI API-key and ChatGPT OAuth catalog")
  selected = true
  callback(nil) -- cancel without opening a browser or collecting a key
end
util.notify = function(message, level)
  if level == vim.log.levels.ERROR then
    failures[#failures + 1] = tostring(message)
  end
end

local ok, err = pcall(vim.cmd, "Phenix auth")
assert(ok, tostring(err))
assert(vim.wait(30000, function() return selected or #failures > 0 end, 20),
  "P1 ACP failed to return installed auth provider picker")
vim.ui.select = original_select
util.notify = original_notify
assert(#failures == 0, vim.inspect(failures))
assert(selected, "provider picker was not reached")

-- Run the installed API-key onboarding to its actual source picker with the
-- shipped ACP kernel, then cancel *before* collecting a key or env variable.
-- A metadata-only catalog alone must not pass this test.
local source_picker, method_picker = nil, false
local secret_requested, browser_requested, env_requested = false, false, false
local input_secret = util.input_secret
local input = vim.ui.input
local open = vim.ui.open
local auth_ui = require("phenix_nvim.ui.auth")
local native_select = auth_ui.select
auth_ui.select = function(items, opts, callback)
  if opts.prompt == "Phenix provider (declared, not authenticated)" then
    for _, item in ipairs(items) do
      if item.id == "openai" then callback(item); return end
    end
    error("installed combined P1 provider catalog has no OpenAI")
  elseif opts.prompt:match("^Authenticate ") then
    method_picker = true
    for _, item in ipairs(items) do
      if item.provider_id == "openai" and item.connection_id == "api"
        and item.kind == "ApiKey" then
        callback(item)
        return
      end
    end
    error("installed P1 runtime has no authorized API-key connection")
  elseif opts.prompt:find("API key source", 1, true) then
    local offered = {}
    for _, item in ipairs(items) do offered[item] = true end
    source_picker = offered
    callback(nil) -- cancellation: never submit credentials
  else
    error("unexpected installed P1 auth stage: " .. tostring(opts.prompt))
  end
end
util.input_secret = function()
  secret_requested = true
  error("source-picker smoke must not request an API key")
end
vim.ui.input = function()
  env_requested = true
  error("source-picker smoke must not request an environment variable")
end
vim.ui.open = function()
  browser_requested = true
  error("API-key source-picker smoke must not launch OAuth browser")
end
local began, begin_error = pcall(vim.cmd, "Phenix auth")
assert(began, tostring(begin_error))
assert(vim.wait(30000, function() return source_picker ~= nil or #failures > 0 end, 20),
  "combined P1 runtime did not reach authorized API-key source chooser")
auth_ui.select = native_select
util.input_secret = input_secret
vim.ui.input = input
vim.ui.open = open
assert(#failures == 0, vim.inspect(failures))
assert(method_picker, "native method list was not reached")
assert(source_picker and source_picker["Enter API key"]
  and source_picker["Read from environment variable"],
  "installed API-key account did not expose both authorized source choices")
assert(not secret_requested and not env_requested and not browser_requested,
  "cancelled auth picker attempted a credential or browser side effect")

require("phenix_nvim").disconnect()
print("Installed P1 auth reached provider and API-key source pickers without credential setup")
