local phenix = require("phenix_nvim")

local config = require("phenix_nvim.config").get()
assert(type(config.command) == "string" and config.command ~= "")
assert(config.command ~= "phenix-acp", "distribution must inject the packaged Phenix command")
assert(vim.fn.executable(config.command) == 1, "packaged Phenix command must be executable")

assert(vim.fn.exists(":Phenix") == 2, "distribution must load the Phenix entry command")

-- The distribution pins a nightly with vim.hl.hl_op(); ensure the yank
-- handler is installed and uses the non-deprecated highlighting API.
assert(type(vim.hl.hl_op) == "function", "nightly yank highlighting API is unavailable")
local yank_handlers = vim.api.nvim_get_autocmds({ event = "TextYankPost", group = "highlight_yank" })
assert(#yank_handlers == 1, "distribution must install exactly one yank highlighter")

local statusline = require("phenix.bars.defaults.statusline")
assert(type(statusline.phenix.hl()) == "string")
assert(type(statusline.phenix.text()) == "string")

-- Distribution actions bind directly to installed Neovim feature modules.
for _, mapping in ipairs(require("keymaps").maps) do
  if mapping.action then
    local module_name = mapping.action.module
    assert(type(module_name) == "string", "keymap action needs a module")
    local implementation = require(module_name)
    assert(
      type(implementation[mapping.action.method]) == "function",
      "unknown keymap action: " .. module_name .. "." .. mapping.action.method
    )
  end
end

-- Test the installed leader+n callback and a mocked notifier implementation.
local notifier = require("phenix.features.notifier")
local history = notifier.history
local calls = 0
notifier.history = function()
  calls = calls + 1
end
local notification_map = vim.fn.maparg("<leader>n", "n", false, true)
assert(notification_map.desc == "Notification history", "<leader>n must open notification history")
assert(type(notification_map.callback) == "function", "<leader>n must have a Lua callback")
local ok, err = pcall(notification_map.callback)
notifier.history = history
assert(ok, tostring(err))
assert(calls == 1, "<leader>n must use the notification feature directly")

-- Git status in bars is read from the Git feature, without a global registry.
local git = require("phenix.features.git")
local git_status = git.status
git.status = function()
  return { head = "phenix-git-regression" }
end
local render_ok, rendered = pcall(require("phenix.bars").render, "statusline")
git.status = git_status
assert(render_ok, tostring(rendered))
assert(rendered:find("phenix-git-regression", 1, true), "statusline must render Git status")

-- The removed facade is not a runtime dependency.
assert(package.loaded["phenix.frontend"] == nil, "legacy frontend facade was loaded")

phenix.disconnect()
print("phenix-nvim distribution configuration smoke passed")
