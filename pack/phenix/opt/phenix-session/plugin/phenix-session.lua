if vim.g.loaded_phenix_session then
  return
end
vim.g.loaded_phenix_session = true

local Frontend = require("phenix.frontend")
local config = Frontend.config("session", {
  resession = {},
  autosave = true,
  restore_cursor = true,
})

local resession = require("resession")
resession.setup(config.resession)
local feature = require("phenix.features.session")
Frontend.register_api("session", feature, {
  contract = { pick = "function", save = "function", load = "function" },
})

if config.autosave then
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      feature.save()
    end,
  })
end

if config.restore_cursor then
  vim.api.nvim_create_autocmd("BufReadPost", {
    callback = function()
      local mark = vim.api.nvim_buf_get_mark(0, '\"')
      local count = vim.api.nvim_buf_line_count(0)
      if mark[1] > 0 and mark[1] <= count then
        vim.api.nvim_win_set_cursor(0, mark)
      end
    end,
  })
end
