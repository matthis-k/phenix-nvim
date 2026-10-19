local phenix = require("phenix_nvim")

local config = require("phenix_nvim.config").get()
assert(type(config.command) == "string" and config.command ~= "")
assert(config.command ~= "phenix-acp", "distribution must inject the packaged Phenix command")
assert(vim.fn.executable(config.command) == 1, "packaged Phenix command must be executable")

assert(vim.fn.exists(":Phenix") == 2, "distribution must load the Phenix entry command")

-- The installed model shortcut must use the canonical command exposed by
-- the runtime-backed client, not the older, equivalent "select" alias.
local model_map = vim.fn.maparg("<leader>pm", "n", false, true)
assert(type(model_map.rhs) == "string" and model_map.rhs:lower():find("phenix model", 1, true),
  "<leader>pm must open the canonical :Phenix model picker")
assert(vim.tbl_contains(require("phenix_nvim.commands").complete("", "Phenix ", #"Phenix "), "model"),
  "installed client must expose the canonical model command")


-- The distribution pins a nightly with vim.hl.hl_op(); ensure the yank
-- handler is installed and uses the non-deprecated highlighting API.
assert(type(vim.hl.hl_op) == "function", "nightly yank highlighting API is unavailable")
local yank_handlers = vim.api.nvim_get_autocmds({ event = "TextYankPost", group = "highlight_yank" })
assert(#yank_handlers == 1, "distribution must install exactly one yank highlighter")

local hl_op, on_yank = vim.hl.hl_op, vim.hl.on_yank
local highlight_calls, deprecated_calls = {}, 0
local original_buffer = vim.api.nvim_get_current_buf()
local yank_buffer = vim.api.nvim_create_buf(false, true)
local clipboard = vim.o.clipboard
local yank_ok, yank_err = pcall(function()
  vim.hl.hl_op = function(opts)
    highlight_calls[#highlight_calls + 1] = opts
    return hl_op(opts)
  end
  vim.hl.on_yank = function()
    deprecated_calls = deprecated_calls + 1
  end
  vim.o.clipboard = ""
  vim.api.nvim_set_current_buf(yank_buffer)
  vim.api.nvim_buf_set_lines(yank_buffer, 0, -1, false, { "yank regression" })
  vim.cmd('normal! "ayy')
  assert(deprecated_calls == 0, "yank handler called deprecated vim.hl.on_yank")
  assert(#highlight_calls == 1, "a real yank must invoke vim.hl.hl_op exactly once")
  assert(highlight_calls[1].higroup == "Visual", "yank highlight must preserve the Visual group")
  local marks = vim.api.nvim_buf_get_extmarks(yank_buffer, -1, 0, -1, { details = true })
  local highlighted = false
  for _, mark in ipairs(marks) do
    if mark[4].hl_group == "Visual" then
      highlighted = true
    end
  end
  assert(highlighted, "a real yank must create a Visual highlight extmark")
end)
vim.hl.hl_op, vim.hl.on_yank = hl_op, on_yank
vim.o.clipboard = clipboard
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(yank_buffer, { force = true })
assert(yank_ok, tostring(yank_err))

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
