---@type PhenixExplorer
local M = {}

function M.open(opts)
  return require("snacks").explorer(opts)
end

return M
