local phenix = require("phenix_nvim")
assert(type(phenix.toggle) == "function")
assert(type(phenix.send) == "function")
assert(type(phenix.new) == "function")
assert(type(phenix.reference) == "function")
assert(type(phenix.choose_session) == "function")
assert(type(phenix.authenticate) == "function")
assert(type(phenix.choose_selection) == "function")
assert(phenix.choose_model == nil)
assert(phenix.choose_routing_profile == nil)

local config = require("phenix_nvim.config").get()
assert(type(config.command) == "string" and config.command ~= "")
assert(config.command ~= "phenix-acp", "Nix package must inject the packaged phenix-acp runtime")
assert(vim.fn.executable(config.command) == 1, "packaged phenix-acp runtime must be executable")

assert(vim.fn.exists(":Phenix") == 2)
assert(vim.fn.exists(":PhenixToggle") == 0)
assert(vim.fn.exists(":PhenixSend") == 0)
assert(vim.fn.exists(":PhenixAuth") == 0)
assert(vim.fn.exists(":PhenixSelect") == 0)
assert(vim.fn.exists(":PhenixModel") == 0)
assert(vim.fn.exists(":PhenixRoute") == 0)

local statusline = require("phenix.bars.defaults.statusline")
assert(type(statusline.phenix.hl()) == "string")
assert(type(statusline.phenix.text()) == "string")

-- Exercise the auto-connected product before bootstrap completes. API presence
-- alone cannot catch a crashed runtime or a stranded readiness callback.
local runtime = require("phenix_nvim.runtime")
local created, create_error
runtime.new_session(function(value, err)
  created, create_error = value, err
end)
assert(vim.wait(30000, function()
  return created ~= nil or create_error ~= nil
end, 10), "distribution startup/session creation timed out")
assert(create_error == nil, vim.inspect(create_error))
local session_id = assert(created.session_id)
assert(runtime.active_session() == session_id)
local selections, selection_error
runtime.list_selections(function(value, err)
  selections, selection_error = value, err
end)
assert(vim.wait(30000, function()
  return selections ~= nil or selection_error ~= nil
end, 10), "distribution selection query timed out")
assert(selection_error == nil, vim.inspect(selection_error))
assert(#selections.available > 0, "packaged routing catalog must not be empty")
for _, selection in ipairs(selections.available) do
  assert(type(selection.provider) == "string" and selection.provider ~= "",
    "packaged runtime must expose typed provider identity")
end

-- Session cleanup must be isolated in the fully packaged distribution. Closing
-- an independent child must not disconnect Phenix or strand the controller.
local child, child_error
runtime.new_session(function(value, err)
  child, child_error = value, err
end)
assert(vim.wait(30000, function()
  return child ~= nil or child_error ~= nil
end, 10), "distribution child session creation timed out")
assert(child_error == nil, vim.inspect(child_error))
local child_id = assert(child.session_id)
assert(child_id ~= session_id)
assert(runtime.active_session() == child_id)

local closed, close_error
runtime.close_session(child_id, function(value, err)
  closed, close_error = value, err
end)
assert(vim.wait(30000, function()
  return closed ~= nil or close_error ~= nil
end, 10), "distribution child session close timed out")
assert(close_error == nil, vim.inspect(close_error))

local controller, controller_error
runtime.resume_session(session_id, function(value, err)
  controller, controller_error = value, err
end)
assert(vim.wait(30000, function()
  return controller ~= nil or controller_error ~= nil
end, 10), "distribution controller resume after child close timed out")
assert(controller_error == nil, vim.inspect(controller_error))
assert(runtime.active_session() == session_id)
assert(runtime.status().connection == "ready", "child close poisoned packaged Phenix connection")

local post_close_selections, post_close_selection_error
runtime.list_selections(function(value, err)
  post_close_selections, post_close_selection_error = value, err
end)
assert(vim.wait(30000, function()
  return post_close_selections ~= nil or post_close_selection_error ~= nil
end, 10), "distribution post-child-close selection query timed out")
assert(post_close_selection_error == nil, vim.inspect(post_close_selection_error))
assert(#post_close_selections.available > 0)

phenix.disconnect()

-- Reuse the same durable database and immediately request resume on reconnect.
local resumed, resume_error
runtime.resume_session(session_id, function(value, err)
  resumed, resume_error = value, err
end)
assert(vim.wait(30000, function()
  return resumed ~= nil or resume_error ~= nil
end, 10), "distribution reconnect/resume timed out")
assert(resume_error == nil, vim.inspect(resume_error))
assert(runtime.active_session() == session_id)
phenix.disconnect()
