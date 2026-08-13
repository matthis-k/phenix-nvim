---@type PhenixPicker
local M = {}

local function picker(name, opts)
  local source = require("snacks").picker[name]
  if type(source) ~= "function" then
    error("Snacks picker source is unavailable: " .. tostring(name))
  end
  return source(opts)
end

setmetatable(M, {
  __index = function(_, name)
    local callback = function(opts)
      return picker(name, opts)
    end
    rawset(M, name, callback)
    return callback
  end,
})

function M.rename_file(opts)
  return require("snacks").rename.rename_file(opts)
end

return M
