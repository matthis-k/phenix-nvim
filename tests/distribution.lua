local phenix = require("phenix_nvim")

local config = require("phenix_nvim.config").get()
assert(type(config.command) == "string" and config.command ~= "")
assert(config.command ~= "phenix-acp", "distribution must inject the packaged Phenix command")
assert(vim.fn.executable(config.command) == 1, "packaged Phenix command must be executable")

assert(vim.fn.exists(":Phenix") == 2, "distribution must load the Phenix entry command")

local statusline = require("phenix.bars.defaults.statusline")
assert(type(statusline.phenix.hl()) == "string")
assert(type(statusline.phenix.text()) == "string")

-- Every distribution action must resolve to an installed feature API.
local frontend = require("phenix.frontend")
local api = frontend.global().api
for _, mapping in ipairs(require("keymaps").maps) do
  if mapping.action then
    local implementation = api[mapping.action.api]
    assert(type(implementation) == "table", "unpublished keymap API: " .. mapping.action.api)
    assert(
      type(implementation[mapping.action.method]) == "function",
      "unknown keymap action: " .. mapping.action.api .. "." .. mapping.action.method
    )
  end
end

-- Exercise the installed leader+n callback rather than calling Snacks directly.
local history = api.notifier.history
local calls = 0
api.notifier.history = function()
  calls = calls + 1
end
local notification_map = vim.fn.maparg("<leader>n", "n", false, true)
assert(notification_map.desc == "Notification history", "<leader>n must open notification history")
assert(type(notification_map.callback) == "function", "<leader>n must have a Lua callback")
local ok, err = pcall(notification_map.callback)
api.notifier.history = history
assert(ok, tostring(err))
assert(calls == 1, "<leader>n must dispatch through the projected notification API")

-- Statusline Git must use the same projected API, not a missing lookup helper.
local git_status = api.git.status
api.git.status = function()
  return { head = "phenix-git-regression" }
end
local render_ok, rendered = pcall(require("phenix.bars").render, "statusline")
api.git.status = git_status
assert(render_ok, tostring(rendered))
assert(rendered:find("phenix-git-regression", 1, true), "statusline must render projected Git status")

phenix.disconnect()
print("phenix-nvim distribution configuration smoke passed")
