if vim.g.loaded_phenix_bars then
  return
end
vim.g.loaded_phenix_bars = true

local bars = require("phenix.bars")
local actions = require("phenix.bars.actions")
local column = require("phenix.bars.statuscolumn")

_G.PhenixBars = _G.PhenixBars or {}
_G.PhenixBars.click = _G.PhenixBars.click or {}
_G.PhenixBars.render = bars.render

bars.register_click("statuscolumn_fold", actions.toggle_mouse_fold)
bars.register_click("statuscolumn_number", actions.focus_mouse_line)
bars.register_click("buffer_focus", actions.focus_buffer)
bars.register_click("buffer_close", actions.close_buffer)
bars.register_click("tab_focus", actions.focus_tab)
bars.register_click("tab_close", actions.close_tab)

-- The library installs surface rendering, not any distribution-specific
-- layout, theme, Git integration or option policy.
vim.o.statusline = "%!v:lua.PhenixBars.render('statusline')"
vim.o.tabline = "%!v:lua.PhenixBars.render('tabline')"
vim.o.statuscolumn = "%!v:lua.PhenixBars.render('statuscolumn')"

local group = vim.api.nvim_create_augroup("PhenixBars", { clear = true })

vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(event)
    column.invalidate(event.match)
  end,
  desc = "Drop closed-window bar snapshots",
})

vim.api.nvim_create_autocmd({
  "BufDelete", "BufWipeout", "BufFilePost", "DiagnosticChanged",
  "TextChanged", "TextChangedI", "BufWritePost",
}, {
  group = group,
  callback = function(event)
    if event.buf and event.buf > 0 then
      column.invalidate_buffer(event.buf)
    else
      column.invalidate()
    end
  end,
  desc = "Invalidate affected statuscolumn buffer snapshots",
})

-- A window can switch buffers without changing its handle: drop the old
-- buffer's snapshot instead of reusing its signs and geometry.
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  group = group,
  callback = function()
    column.invalidate(vim.api.nvim_get_current_win())
  end,
  desc = "Invalidate column state when a window displays another buffer",
})

vim.api.nvim_create_autocmd({ "WinResized", "WinScrolled" }, {
  group = group,
  callback = function()
    column.invalidate()
  end,
  desc = "Invalidate statuscolumn window geometry",
})

vim.api.nvim_create_autocmd("OptionSet", {
  group = group,
  pattern = { "number", "relativenumber", "numberwidth", "foldcolumn", "signcolumn" },
  callback = function()
    column.invalidate(vim.api.nvim_get_current_win())
  end,
  desc = "Invalidate window column layout after option changes",
})
