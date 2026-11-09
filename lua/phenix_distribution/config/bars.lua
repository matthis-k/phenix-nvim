-- The distribution chooses UI composition. phenix-bars itself only owns
-- rendering, interactions and statuscolumn snapshot mechanics.
local bars = require("phenix.bars")
local column = require("phenix.bars.statuscolumn")
local statusline = require("phenix_distribution.bars.statusline")
local statuscolumn = require("phenix_distribution.bars.statuscolumn")
local tabline = require("phenix_distribution.bars.tabline")

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

local group = vim.api.nvim_create_augroup("PhenixBarsDistribution", { clear = true })

-- Buffer metadata (names/icons/current flags) is much less volatile than text,
-- signs and diagnostics. Keep the expensive cache rebuilds off the typing path.
vim.api.nvim_create_autocmd({
  "BufAdd", "BufDelete", "BufEnter", "BufFilePost", "BufModifiedSet",
}, {
  group = group,
  callback = function()
    statusline.init_cache()
    tabline.init_cache()
    vim.cmd.redrawstatus()
    vim.cmd.redrawtabline()
  end,
  desc = "Refresh distribution buffer labels and icons",
})

vim.api.nvim_create_autocmd("DiagnosticChanged", {
  group = group,
  callback = function()
    vim.cmd.redrawstatus()
    vim.cmd.redrawtabline()
  end,
  desc = "Refresh diagnostic labels",
})

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
  group = group,
  callback = function()
    vim.cmd.redrawstatus()
  end,
  desc = "Refresh modified indicator without rebuilding metadata",
})

vim.api.nvim_create_autocmd("ModeChanged", {
  group = group,
  callback = function()
    vim.cmd.redrawtabline()
  end,
  desc = "Refresh mode-dependent tabline labels",
})

vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function()
    tabline.invalidate_highlights()
    vim.cmd.redrawstatus()
    vim.cmd.redrawtabline()
  end,
  desc = "Regenerate distribution tabline highlights after theme changes",
})

vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = { "GitSignsUpdate", "PhenixGitRemoteUpdate" },
  callback = function(event)
    if event.buf and event.buf > 0 then
      column.invalidate_buffer(event.buf)
    else
      column.invalidate()
    end
    vim.cmd.redrawstatus()
  end,
  desc = "Refresh bar Git projections after provider notifications",
})

return bars
