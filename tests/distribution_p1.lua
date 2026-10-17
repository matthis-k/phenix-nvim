-- End-to-end Basic distribution test. It runs in the installed nvim-nix-basic.
local frontend = require("phenix_nvim")
local config = require("phenix_nvim.config").get()
local runtime = require("phenix_nvim.runtime")
local compose = require("phenix_nvim.compose.buffer")
local transcript = require("phenix_nvim.transcript.model")
assert(config.backend == "p1", "Basic distribution must use P1")
assert(type(config.command) == "string" and config.command:match("/bin/phenix%-basic%-acp$"))
assert(vim.fn.executable(config.command) == 1, "P1 package must ship its ACP executable")
assert(runtime.p1_active(), "P1 distribution must not use the old native runtime")
assert(package.loaded["phenix.frontend"] == nil, "distribution reintroduced old frontend facade")
assert(vim.fn.exists(":Phenix") == 2, "missing integrated chat command")
local commands = require("phenix_nvim.commands")
local roots = commands.complete("", "Phenix ", #"Phenix ")
assert(vim.tbl_contains(roots, "auth"), "installed client must expose :Phenix auth")
assert(vim.tbl_contains(roots, "model"), "installed client must expose :Phenix model")
-- P1 does not claim credential import or writable model selection before
-- runtime #891 ships. UI capability discovery remains authoritative.


local surface = assert(frontend.new("sidebar"))
local buffer = compose.ensure(surface.compose)
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "hello" })
frontend.send()
local function has_both_speakers()
  local id = surface.session_id
  if not id then return false end
  local snapshot = runtime.session_state().sessions[id]
  if not snapshot then return false end
  local rendered = transcript.rebuild(snapshot)
  if not rendered then return false end
  local found_user, found_agent = false, false
  for _, key in ipairs(rendered.order) do
    local node = rendered.nodes[key]
    if node.role == "user" and node.text == "hello" then found_user = true end
    if node.role == "assistant" and node.text == "mock:hello" then found_agent = true end
  end
  return found_user and found_agent
end
assert(vim.wait(30000, has_both_speakers, 20),
  "Basic distribution did not render the P1 prompt and answer")
local id = assert(surface.session_id)

-- Verify the actual :Phenix capabilities command renders the runtime-owned
-- model binding, rather than a static Lua-side provider or selection.
local util = require("phenix_nvim.util")
local original_notify = util.notify
local capabilities_notice
util.notify = function(message, level)
  capabilities_notice = { message = message, level = level }
end
local command_ok, command_error = pcall(vim.cmd, "Phenix capabilities")
assert(vim.wait(10000, function() return capabilities_notice ~= nil end, 20),
  "P1 distribution did not display the negotiated capabilities")
util.notify = original_notify
assert(command_ok, tostring(command_error))
assert(capabilities_notice.level == vim.log.levels.INFO, capabilities_notice.message)
assert(capabilities_notice.message:find("acp-v1", 1, true), "missing ACP transport")
assert(capabilities_notice.message:find("phenix.model.scripted", 1, true),
  "capabilities must show the runtime-selected model")
assert(not capabilities_notice.message:find("model_selection = true", 1, true),
  "P1 must not advertise model selection without runtime management")

frontend.disconnect()
local reloaded, failure
runtime.resume_session(id, function(value, err) reloaded, failure = value, err end)
assert(vim.wait(30000, function() return reloaded ~= nil or failure ~= nil end, 20),
  "Basic distribution could not reload a durable session")
assert(not failure and reloaded.session_id == id)
assert(has_both_speakers(), "Basic distribution lost the journal replay")
frontend.disconnect()
print("P1 Basic packaged Neovim distribution accepted")
