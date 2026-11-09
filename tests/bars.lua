-- Focused rendering regressions run in the real packaged Neovim environment.
local bars = require("phenix.bars")
local render = bars.render_part

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %q, got %q", expected, actual))
end

-- Dynamic data is literal. Only an explicit raw field emits statusline tokens.
equal(render({ text = "100% complete" }), "100%% complete")
equal(render({ raw = "%=" }), "%=")
equal(render({ text = "a%b", before = "<", after = ">" }), "<a%%b>")
equal(render({ text = "hidden", enabled = false }), "")
equal(render({ children = {
  { text = "first" },
  { text = "ignored", enabled = false },
  { text = "third" },
}, child_sep = " " }), "first third")

-- Child styling must restore the enclosing highlight; siblings must not inherit
-- a highlight they did not explicitly request.
equal(render({
  hl = "Parent",
  child_sep = "|",
  children = {
    { hl = "Child", text = "one" },
    { text = "two" },
  },
}), "%#Parent#%#Child#one%#Parent#|two%*")
equal(render({
  children = { { hl = "Child", text = "one" }, { text = "two" } },
}), "%#Child#one%*two")

equal(render({ text = "open", on_click = "buffer_focus", on_click_param = 12 }),
  "%12@v:lua.PhenixBars.click.buffer_focus@open%T")
assert(not pcall(render, { text = "broken", on_click_param = "0@evil", on_click = "buffer_focus" }))
assert(not pcall(render, { text = "broken", hl = "Invalid#Group" }))
assert(not pcall(render, { text = "broken", raw = "%=" }))

local ctx = { value = "from-context" }
equal(render({ text = function(given) return given.value end }, ctx), "from-context")

-- Rendering the tabline must work even if a listed buffer has diagnostics.
local tabline = require("phenix_distribution.bars.tabline")
local buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buffer, "phenix-bars-regression.lua")
local get_diagnostics = vim.diagnostic.get
local success, failure = pcall(function()
  vim.diagnostic.get = function(buf, opts)
    if buf == buffer and opts and opts.severity == vim.diagnostic.severity.ERROR then
      return { {} }
    end
    return {}
  end
  tabline.init_cache()
  local output = render(tabline.buffer(buffer))
  assert(output:find("1 ", 1, true), "tabline must render a buffer diagnostic")
end)
vim.diagnostic.get = get_diagnostics
vim.api.nvim_buf_delete(buffer, { force = true })
assert(success, tostring(failure))

-- Open-fold continuation lines must not all be reported as fold headers.
local column = require("phenix.bars.statuscolumn")
local foldbuf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(foldbuf, 0, -1, false, { "a", "b", "c", "d", "e", "f" })
local win = vim.api.nvim_get_current_win()
local previous_buf = vim.api.nvim_win_get_buf(win)
local foldmethod = vim.wo[win].foldmethod
local foldlevel = vim.wo[win].foldlevel
local foldenable = vim.wo[win].foldenable
local fold_success, fold_error = pcall(function()
  vim.api.nvim_win_set_buf(win, foldbuf)
  vim.wo[win].foldmethod = "manual"
  vim.wo[win].foldlevel = 99
  vim.wo[win].foldenable = true
  vim.cmd("2,5fold")
  vim.cmd("normal! zR")
  local header = column.fold_info(2, win)
  local continuation = column.fold_info(3, win)
  assert(header and header.start == 2, "open fold header not detected")
  assert(continuation and continuation.start ~= 3, "continuation rendered as a fold header")
end)
vim.api.nvim_win_set_buf(win, previous_buf)
vim.wo[win].foldmethod = foldmethod
vim.wo[win].foldlevel = foldlevel
vim.wo[win].foldenable = foldenable
vim.api.nvim_buf_delete(foldbuf, { force = true })
assert(fold_success, tostring(fold_error))

-- Reuse of a window handle must never reuse a snapshot from its old buffer.
local first = vim.api.nvim_create_buf(true, false)
local second = vim.api.nvim_create_buf(true, false)
local swap_win = vim.api.nvim_get_current_win()
local old_buf = vim.api.nvim_win_get_buf(swap_win)
local swap_ok, swap_err = pcall(function()
  vim.api.nvim_win_set_buf(swap_win, first)
  assert(column.get(swap_win).buf == first)
  vim.api.nvim_win_set_buf(swap_win, second)
  assert(column.get(swap_win).buf == second, "statuscolumn reused stale window snapshot")
end)
vim.api.nvim_win_set_buf(swap_win, old_buf)
vim.api.nvim_buf_delete(first, { force = true })
vim.api.nvim_buf_delete(second, { force = true })
assert(swap_ok, tostring(swap_err))

print("phenix-bars rendering and fold regressions passed")
