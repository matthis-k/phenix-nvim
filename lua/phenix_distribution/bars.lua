local bars = require("phenix.bars")
local actions = require("phenix.bars.actions")
local statuscolumn_state = require("phenix.bars.statuscolumn")
local statusline = require("ui.statusline")
local statuscolumn = require("ui.statuscolumn")
local tabline = require("ui.tabline")

bars.register_click("statuscolumn_fold", actions.toggle_mouse_fold)
bars.register_click("statuscolumn_number", actions.focus_mouse_line)
bars.register_click("buffer_focus", actions.focus_buffer)
bars.register_click("buffer_close", actions.close_buffer)
bars.register_click("tab_focus", actions.focus_tab)
bars.register_click("tab_close", actions.close_tab)

bars.configure({
  statusline = statusline.whole,
  statuscolumn = statuscolumn.whole,
  tabline = tabline.whole,
})

vim.o.laststatus = 3
vim.o.showtabline = 2
vim.o.numberwidth = 4

statusline.init_cache()
tabline.init_cache()

local group = vim.api.nvim_create_augroup("PhenixDistributionBars", { clear = true })

vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufEnter", "BufFilePost", "DiagnosticChanged" }, {
  group = group,
  callback = function()
    statusline.init_cache()
    tabline.init_cache()
    vim.cmd.redrawstatus()
    vim.cmd.redrawtabline()
  end,
  desc = "Refresh Phenix distribution statusline and tabline data",
})

vim.api.nvim_create_autocmd({ "ModeChanged", "DiagnosticChanged" }, {
  group = group,
  callback = function()
    vim.cmd.redrawtabline()
  end,
  desc = "Redraw Phenix distribution tabline after visible state changes",
})

-- Gitsigns owns these extmarks. Keep its update event in the integration layer;
-- the generic bars mechanism only provides cache invalidation.
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = "GitSignsUpdate",
  callback = function()
    statuscolumn_state.invalidate()
  end,
  desc = "Invalidate Phenix statuscolumn after Gitsigns updates",
})
