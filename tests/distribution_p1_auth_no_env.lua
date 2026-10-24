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
require("phenix_nvim").disconnect()
print("Installed :Phenix auth reached provider selection with zero credential variables")
