if vim.g.loaded_phenix_bars then
  return
end
vim.g.loaded_phenix_bars = true

local Frontend = require("phenix.frontend")
local bars = require("phenix.bars")
local actions = require("phenix.bars.actions")
local statuscolumn_state = require("phenix.bars.statuscolumn")
local statusline = require("phenix.bars.defaults.statusline")
local statuscolumn = require("phenix.bars.defaults.statuscolumn")
local tabline = require("phenix.bars.defaults.tabline")

_G.PhenixBars = _G.PhenixBars or {}
_G.PhenixBars.click = _G.PhenixBars.click or {}
_G.PhenixBars.render = function(surface)
  return bars.render(surface)
end

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

vim.o.statusline = "%!v:lua.PhenixBars.render('statusline')"
vim.o.tabline = "%!v:lua.PhenixBars.render('tabline')"
vim.o.statuscolumn = "%!v:lua.PhenixBars.render('statuscolumn')"
vim.o.laststatus = 3
vim.o.showtabline = 2
vim.o.numberwidth = 4

statusline.init_cache()
tabline.init_cache()
Frontend.provide("bars", bars)

local group = vim.api.nvim_create_augroup("PhenixBars", { clear = true })

vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(event)
    statuscolumn_state.invalidate(event.match)
  end,
  desc = "Drop closed-window Phenix bar state",
})

vim.api.nvim_create_autocmd({
  "BufAdd",
  "BufDelete",
  "BufEnter",
  "BufFilePost",
  "BufWritePost",
  "DiagnosticChanged",
  "TextChanged",
  "TextChangedI",
  "WinResized",
  "WinScrolled",
}, {
  group = group,
  callback = function()
    statuscolumn_state.invalidate()
    statusline.init_cache()
    tabline.init_cache()
    vim.cmd.redrawstatus()
    vim.cmd.redrawtabline()
  end,
  desc = "Refresh Phenix bar state after visible editor changes",
})

vim.api.nvim_create_autocmd({ "ModeChanged", "DiagnosticChanged" }, {
  group = group,
  callback = function()
    vim.cmd.redrawtabline()
  end,
  desc = "Redraw Phenix tabline after visible state changes",
})

vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = "GitSignsUpdate",
  callback = function()
    statuscolumn_state.invalidate()
    vim.cmd.redrawstatus()
  end,
  desc = "Refresh Phenix bars after Git integration updates",
})

vim.api.nvim_create_autocmd("OptionSet", {
  group = group,
  pattern = { "number", "relativenumber", "numberwidth", "foldcolumn", "signcolumn" },
  callback = function()
    statuscolumn_state.invalidate(vim.api.nvim_get_current_win())
  end,
  desc = "Invalidate Phenix statuscolumn after window option changes",
})
