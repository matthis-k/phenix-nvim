---@type PhenixNotifier
local M = {}

function M.history()
  return require("snacks").notifier.show_history()
end

function M.hide()
  return require("snacks").notifier.hide()
end

return M
