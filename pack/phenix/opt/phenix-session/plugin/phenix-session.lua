if vim.g.loaded_phenix_session then
  return
end
vim.g.loaded_phenix_session = true

local resession = require("resession")
resession.setup({})
local feature = require("phenix.features.session")
require("phenix.frontend").provide("session", feature, {
  contract = { pick = "function", save = "function", load = "function" },
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    feature.save()
  end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '\"')
    local count = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= count then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
})
