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
equal(render({
  on_click = "parent",
  child_sep = "|",
  children = {
    { text = "before" },
    { text = "inside", on_click = "child" },
    { text = "after" },
  },
}), "%@v:lua.PhenixBars.click.parent@before|%@v:lua.PhenixBars.click.child@inside%T%@v:lua.PhenixBars.click.parent@|after%T")
assert(not pcall(render, { text = "broken", on_click_param = "0@evil", on_click = "buffer_focus" }))
assert(not pcall(render, { text = "broken", hl = "Invalid#Group" }))
assert(not pcall(render, { text = "broken", raw = "%=" }))

local ctx = { value = "from-context" }
equal(render({ text = function(given) return given.value end }, ctx), "from-context")

-- Per-render memoization must preserve nil as a cached result and reset
-- on the next complete render, without preserving stale UI state.
local previous_spec = bars.current().statusline
local memo_calls = 0
local memo_spec = {
  children = {
    { text = function(ctx)
      return ctx.memo("missing", function()
        memo_calls = memo_calls + 1
        return nil
      end) or "empty"
    end },
    { text = function(ctx)
      return ctx.memo("missing", function()
        memo_calls = memo_calls + 1
        return nil
      end) or "empty"
    end },
  },
}
local memo_ok, memo_error = pcall(function()
  bars.configure({ statusline = memo_spec })
  equal(bars.render("statusline"), "emptyempty")
  assert(memo_calls == 1, "nil memo result computed twice within one render")
  equal(bars.render("statusline"), "emptyempty")
  assert(memo_calls == 2, "memo result leaked between separate renders")
end)
bars.configure({ statusline = previous_spec })
assert(memo_ok, tostring(memo_error))

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

-- Global statusline evaluation may target an inactive window. Every field
-- must derive buffer and cursor data from the rendered window, not current 0.
local statusline = require("phenix_distribution.bars.statusline")
local other_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, { "different buffer", "second line" })
vim.bo[other_buf].filetype = "python"
vim.bo[other_buf].readonly = true
local other_win = vim.api.nvim_open_win(other_buf, false, {
  relative = "editor", width = 30, height = 2, row = 1, col = 1, style = "minimal",
})
local old_statusline_winid = vim.g.statusline_winid
local context_ok, context_err = pcall(function()
  vim.api.nvim_win_set_cursor(other_win, { 2, 3 })
  vim.g.statusline_winid = other_win
  local display = bars.render("statusline")
  assert(display:find("python", 1, true), "inactive-window filetype missing")
  assert(display:find("readonly", 1, true), "inactive-window readonly flag missing")
  assert(display:find("002:04", 1, true), "inactive-window cursor position missing")
  assert(render(statusline.readonly, { buf = other_buf }) == "%#@error#readonly%*")
end)
vim.g.statusline_winid = old_statusline_winid
vim.api.nvim_win_close(other_win, true)
vim.api.nvim_buf_delete(other_buf, { force = true })
assert(context_ok, tostring(context_err))

-- Path shortening measures terminal cells, not bytes. Keep short-on-screen
-- UTF-8 paths intact and avoid slicing codepoints in shortened directories.
local short_unicode = vim.api.nvim_create_buf(true, false)
local long_unicode = vim.api.nvim_create_buf(true, false)
local unicode_ok, unicode_err = pcall(function()
  local visual_short = "/home/" .. string.rep("é", 40) .. "/src/example.lua"
  local visual_long = "/home/" .. string.rep("é", 90) .. "/src/example.lua"
  vim.api.nvim_buf_set_name(short_unicode, visual_short)
  vim.api.nvim_buf_set_name(long_unicode, visual_long)
  statusline.init_cache()
  local short_result = render(statusline.filename, { buf = short_unicode })
  assert(short_result:find(visual_short, 1, true),
    "display-short Unicode path should not be abbreviated")
  local long_result = render(statusline.filename, { buf = long_unicode })
  assert(long_result:find("ééééé…", 1, true),
    "abbreviated Unicode directory was truncated by bytes")
end)
vim.api.nvim_buf_delete(short_unicode, { force = true })
vim.api.nvim_buf_delete(long_unicode, { force = true })
statusline.init_cache()
assert(unicode_ok, tostring(unicode_err))

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
  vim.api.nvim_win_set_cursor(win, { 3, 0 })
  column.invalidate(win)
  local snapshot = column.get_with_cursor(win)
  assert(snapshot.current_fold.start == 3 and snapshot.current_fold["end"] == 3,
    "open-fold highlight leaked onto unrelated preceding lines")
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
