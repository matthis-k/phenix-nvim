---@type PhenixLsp
local api = {
  diagnostic_open = vim.diagnostic.open_float,
  diagnostic_prev = function()
    return vim.diagnostic.jump({ count = -1 })
  end,
  diagnostic_next = function()
    return vim.diagnostic.jump({ count = 1 })
  end,
  code_action = vim.lsp.buf.code_action,
  declaration = vim.lsp.buf.declaration,
  hover = vim.lsp.buf.hover,
  inlay_toggle = function()
    return vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
  end,
  rename = vim.lsp.buf.rename,
  workspace_add = vim.lsp.buf.add_workspace_folder,
  workspace_remove = vim.lsp.buf.remove_workspace_folder,
  workspace_list = function()
    vim.print(vim.lsp.buf.list_workspace_folders())
  end,
}

require("phenix.frontend").register_api("lsp", api, {
  contract = {
    diagnostic_open = "function",
    diagnostic_prev = "function",
    diagnostic_next = "function",
    code_action = "function",
    declaration = "function",
    hover = "function",
    inlay_toggle = "function",
    rename = "function",
    workspace_add = "function",
    workspace_remove = "function",
    workspace_list = "function",
  },
})
