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
