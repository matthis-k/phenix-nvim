---@class PhenixLsp
---@field definition fun(): any
---@field references fun(): any
---@field rename fun(): any
---@field code_action fun(): any
local api = {
  definition = vim.lsp.buf.definition,
  references = vim.lsp.buf.references,
  rename = vim.lsp.buf.rename,
  code_action = vim.lsp.buf.code_action,
}
require("phenix.frontend").provide("lsp", api)
