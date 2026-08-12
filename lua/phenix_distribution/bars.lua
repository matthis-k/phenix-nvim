local bars = require("phenix.bars")
local statusline = require("ui.statusline")
local statuscolumn = require("ui.statuscolumn")
local tabline = require("ui.tabline")

bars.configure({
  statusline = statusline.whole,
  statuscolumn = statuscolumn.whole,
  tabline = tabline.whole,
})

vim.o.laststatus = 3
vim.o.showtabline = 2
vim.o.numberwidth = 4

statusline.init_cache()
statuscolumn.init_cache()
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
  desc = "Refresh Phenix statusline and tabline configuration caches",
})

vim.api.nvim_create_autocmd({
  "BufEnter",
  "CursorMoved",
  "CursorMovedI",
  "DiagnosticChanged",
  "TextChanged",
  "TextChangedI",
  "WinEnter",
  "WinResized",
  "WinScrolled",
}, {
  group = group,
  callback = function()
    statuscolumn.init_cache()
  end,
  desc = "Refresh Phenix statuscolumn configuration cache",
})

vim.api.nvim_create_autocmd("OptionSet", {
  group = group,
  pattern = { "number", "relativenumber", "numberwidth", "foldcolumn", "signcolumn" },
  callback = function()
    statuscolumn.init_cache()
  end,
  desc = "Refresh Phenix statuscolumn after window option changes",
})

vim.api.nvim_create_autocmd({ "ModeChanged", "DiagnosticChanged" }, {
  group = group,
  callback = function()
    vim.cmd.redrawtabline()
  end,
  desc = "Redraw Phenix tabline after visible state changes",
})
