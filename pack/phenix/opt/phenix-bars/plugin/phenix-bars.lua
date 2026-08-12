if vim.g.loaded_phenix_bars then
  return
end
vim.g.loaded_phenix_bars = true

_G.PhenixBars = _G.PhenixBars or {}
_G.PhenixBars.click = _G.PhenixBars.click or {}
_G.PhenixBars.render = function(surface)
  return require("phenix.bars").render(surface)
end

vim.o.statusline = "%!v:lua.PhenixBars.render('statusline')"
vim.o.tabline = "%!v:lua.PhenixBars.render('tabline')"
vim.o.statuscolumn = "%!v:lua.PhenixBars.render('statuscolumn')"

local group = vim.api.nvim_create_augroup("PhenixBars", { clear = true })

vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(event)
    require("phenix.bars.statuscolumn").invalidate(event.match)
  end,
  desc = "Drop closed-window Phenix bar state",
})

vim.api.nvim_create_autocmd({
  "BufEnter",
  "BufWritePost",
  "DiagnosticChanged",
  "TextChanged",
  "TextChangedI",
  "WinResized",
  "WinScrolled",
}, {
  group = group,
  callback = function()
    require("phenix.bars.statuscolumn").invalidate()
  end,
  desc = "Invalidate Phenix statuscolumn state after editor changes",
})

vim.api.nvim_create_autocmd("OptionSet", {
  group = group,
  pattern = { "number", "relativenumber", "numberwidth", "foldcolumn", "signcolumn" },
  callback = function()
    require("phenix.bars.statuscolumn").invalidate(vim.api.nvim_get_current_win())
  end,
  desc = "Invalidate Phenix statuscolumn after window option changes",
})
