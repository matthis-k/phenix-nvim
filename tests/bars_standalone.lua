-- Launch with -u NONE and the bare phenix-bars directory on runtimepath.
-- This must work without Phenix distribution, Git, icons, or theme packages.
local root = vim.fn.getcwd()
local package_root = root .. "/pack/phenix/opt/phenix-bars"
vim.opt.runtimepath:prepend(package_root)

assert(package.loaded["phenix_distribution.config.bars"] == nil)
assert(package.loaded["phenix.features.git"] == nil)
assert(package.loaded["nvim-web-devicons"] == nil)
assert(package.loaded["constants"] == nil)

dofile(package_root .. "/plugin/phenix-bars.lua")
local bars = require("phenix.bars")
local column = require("phenix.bars.statuscolumn")

assert(vim.o.statusline:find("PhenixBars.render", 1, true))
assert(type(_G.PhenixBars.click.buffer_focus) == "function")
assert(bars.render("statusline"):find("%f", 1, true))

bars.configure({
  statusline = {
    children = {
      { text = "literal%value" },
      { raw = "%=" },
      { text = function(ctx) return ctx.surface end },
    },
  },
})
local rendered = bars.render("statusline")
assert(rendered:find("literal%%value", 1, true), "literal content was not escaped")
assert(rendered:find("%=", 1, true), "raw statusline token was not preserved")
assert(rendered:find("statusline", 1, true), "render context was not propagated")

local current = bars.current()
assert(type(current.statusline) == "table")
current.statusline.children = {}
assert(bars.render("statusline") ~= "", "current() leaked mutable config state")

local marks = vim.api.nvim_create_namespace("phenix-bars-standalone")
local win = vim.api.nvim_get_current_win()
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "sign test" })
column.configure_sign_column("test", { width = 2 })
vim.api.nvim_buf_set_extmark(buf, marks, 0, 0, {
  sign_text = "A",
  sign_hl_group = "DiagnosticInfo",
})
local snapshot = assert(column.get(win))
assert(snapshot.buf == buf)
assert(snapshot.sign_columns.test.width == 2)
assert(snapshot.sign_columns.test.assigned[1] ~= nil, "sign was not discovered")
column.invalidate(win)
assert(column.get(win) ~= snapshot, "invalidation must replace a cached snapshot")
column.remove_sign_column("test")

assert(package.loaded["phenix_distribution.config.bars"] == nil)
assert(package.loaded["phenix.features.git"] == nil)
assert(package.loaded["nvim-web-devicons"] == nil)
assert(package.loaded["constants"] == nil)

print("standalone phenix-bars package passed")
