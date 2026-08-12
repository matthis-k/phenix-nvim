---@type PhenixDashboard
local M = {}

function M.open(opts)
  return require("snacks").dashboard.open(opts)
end

return M
