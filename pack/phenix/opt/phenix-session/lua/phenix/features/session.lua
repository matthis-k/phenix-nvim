---@type PhenixSessionFeature
local M = {}

function M.pick()
  return require("pick-resession").pick()
end

function M.save(name)
  return require("resession").save(name or vim.fn.getcwd(), { notify = false })
end

function M.load(name)
  return require("resession").load(name or vim.fn.getcwd(), { silence_errors = true })
end

return M
