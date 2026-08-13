---@type PhenixTerminal
local M = {}

function M.toggle(opts)
  return require("snacks").terminal(opts)
end

return M
