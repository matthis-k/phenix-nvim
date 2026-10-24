-- Installed default nvim-nix must use native provider management through
-- official ACP, while preserving the real Basic prompt/model lifecycle.
local frontend = require("phenix_nvim")
local config = require("phenix_nvim.config").get()
local runtime = require("phenix_nvim.runtime")
local util = require("phenix_nvim.util")
assert(config.backend == "p1")
assert(type(config.command) == "string"
  and config.command:match("/bin/phenix%-basic%-managed%-acp$"),
  "default distribution must install the managed native ACP host")
assert(vim.fn.executable(config.command) == 1)
assert(runtime.p1_active())

local commands = require("phenix_nvim.commands")
local roots = commands.complete("", "Phenix ", #"Phenix ")
assert(vim.tbl_contains(roots, "providers"),
  "default distribution must expose :Phenix providers")

local select_original, notify_original = vim.ui.select, util.notify
local picker_count, detail, error_notice = 0, nil, nil
vim.ui.select = function(items, options, callback)
  picker_count = picker_count + 1
  assert(options.prompt == "Installed Phenix providers (not authenticated)")
  local offered = {}
  local chosen
  for _, item in ipairs(items) do
    offered[item.id] = true
    if item.id == "openai" then chosen = item end
  end
  for _, name in ipairs({
    "openai", "openrouter", "anthropic", "opencode-zen", "opencode-go", "zai",
  }) do
    assert(offered[name], "installed native catalog omitted " .. name)
  end
  assert(chosen and #chosen.connections >= 2)
  callback(chosen)
end
util.notify = function(message, level)
  if level == vim.log.levels.INFO then
    detail = message
  else
    error_notice = { message = message, level = level }
  end
end
local ok, err = pcall(vim.cmd, "Phenix providers")
assert(ok, tostring(err))
assert(vim.wait(30000, function()
  return detail ~= nil or error_notice ~= nil
end, 20), "native provider discovery did not return to installed editor")
vim.ui.select, util.notify = select_original, notify_original
assert(error_notice == nil, vim.inspect(error_notice))
assert(picker_count == 1, "provider picker must be driven once")
assert(detail:find("registered, not authenticated", 1, true))
assert(detail:find("OpenAI API", 1, true), detail)
assert(detail:find("ChatGPT", 1, true), detail)

-- Registration does not imply credential-write authority. The managed
-- default has no launcher-scoped credential composition; auth must fail
-- without asking Neovim to collect a secret it cannot use.
local previous_notify = util.notify
local previous_secret = util.input_secret
local previous_input = vim.ui.input
local previous_open = vim.ui.open
local previous_select_auth = vim.ui.select
local auth_notice, secret_prompted, browser_opened, auth_picker_count
secret_prompted, browser_opened, auth_picker_count = false, false, 0
util.notify = function(message, level)
  auth_notice = { message = tostring(message), level = level }
end
util.input_secret = function()
  secret_prompted = true
end
vim.ui.input = function()
  secret_prompted = true
end
vim.ui.open = function()
  browser_opened = true
end
-- Catalog metadata can advertise the *kind* of OAuth, but this default
-- composition contains only the offline metadata provider, not an OAuth
-- backend. Selecting its advertised method must reach a denied begin(),
-- never request a key or open a browser as if the account were authorized.
vim.ui.select = function(items, options, callback)
  auth_picker_count = auth_picker_count + 1
  local chosen
  if options.prompt == "Phenix provider (declared, not authenticated)" then
    for _, provider in ipairs(items) do
      if provider.id == "openai" then chosen = provider end
    end
  elseif options.prompt:find("^Authenticate ") then
    for _, method in ipairs(items) do
      if method.kind == "OAuthAuthorizationCode" then chosen = method end
    end
  else
    error("unexpected auth picker: " .. tostring(options.prompt))
  end
  assert(chosen, "missing installed ChatGPT OAuth catalog choice")
  callback(chosen)
end
local auth_ok, auth_err = pcall(vim.cmd, "Phenix auth")
assert(auth_ok, tostring(auth_err))
assert(vim.wait(10000, function() return auth_notice ~= nil end, 20),
  "unconfigured OAuth attempt did not report the provider denial")
util.notify = previous_notify
util.input_secret = previous_secret
vim.ui.input = previous_input
vim.ui.open = previous_open
vim.ui.select = previous_select_auth
-- A single OAuth option is dispatched without a picker; multiple options
-- use the explicit selector. Both must end at the same unconfigured-provider
-- denial and never initiate secret collection or a browser launch.
assert(auth_picker_count <= 2, "unexpected nested authentication picker")
assert(not secret_prompted, "ungranted managed host requested a secret")
assert(not browser_opened, "ungranted managed host opened an authorization URL")
assert(auth_notice.level == vim.log.levels.ERROR
  and #auth_notice.message > 0,
  "unconfigured provider OAuth must fail closed, never report authentication")

-- Independently exercise real ACP with a second controller and fresh
-- Basic session. Listing registrations cannot authorize uninstalled models.
local sdk = require("phenix_client")
local acp = require("phenix_client.acp")
local probe = sdk.new(acp.new({ command = config.command }))
local function await_result(action, label)
  local result, failure, settled
  action(function(value, problem)
    assert(not settled, label .. " callback settled twice")
    result, failure, settled = value, problem, true
  end)
  assert(vim.wait(30000, function() return settled end, 20),
    label .. " timed out")
  assert(not failure and result ~= nil,
    label .. ": " .. vim.inspect(failure))
  return result
end
await_result(function(done) probe:start(done) end, "ACP initialize")
local page = await_result(function(done)
  probe:list_providers(done)
end, "native provider catalog")
assert(page.revision > 0 and #page.providers >= 6)
local session = await_result(function(done)
  probe:new_session(done)
end, "Basic new session")
local models = await_result(function(done)
  probe:list_models(session.session_id, done)
end, "Basic model catalog")
assert(models.selected == "phenix.model.scripted")
assert(#models.models == 1 and models.models[1].id == models.selected)
local answer = await_result(function(done)
  probe:send(session.session_id, "managed-hello", done)
end, "Basic model continuation")
assert(answer.stop_reason == "end_turn")
probe:close()
frontend.disconnect()
print("Installed managed default provider discovery and scripted Basic run accepted")
