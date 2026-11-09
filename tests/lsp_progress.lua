-- Regression checks for the compact, event-driven LSP statusline indicator.
local progress = require("phenix_distribution.bars.lsp_progress")
local bars = require("phenix.bars")
local statusline = require("phenix_distribution.bars.statusline")

local function display()
  return bars.render_part(progress.part)
end

local function contains(haystack, needle)
  assert(haystack:find(needle, 1, true), ("expected %q in %q"):format(needle, haystack))
end

local function absent(haystack, needle)
  assert(not haystack:find(needle, 1, true), ("unexpected %q in %q"):format(needle, haystack))
end

-- The indicator must appear next to the existing diagnostics, not in the
-- tabline or a separate floating UI.
local center = statusline.whole.children[2].children
assert(center[#center] == progress.part, "LSP indicator must follow diagnostics")

progress.clear()
assert(progress.current() == nil and display() == "")

-- A single client shows one spinner, an optional percent, and just the name.
progress.update(8001, "index", { kind = "begin" }, "lua_ls")
contains(display(), "lua_ls")
absent(display(), "%")
progress.update(8001, "index", { kind = "report", percentage = 35 }, "lua_ls")
local one = display()
contains(one, "35%")
contains(one, "lua_ls")
assert(one:find("35%%") < one:find("lua_ls"), "single LSP percent must precede name")
assert(progress.current().count == 1)

-- Two clients switch to an aggregate instead of concatenating full names.
progress.update(8002, "init", { kind = "begin" }, "rust_analyzer")
local aggregate = display()
contains(aggregate, "2 LSPs loading")
absent(aggregate, "lua_ls")
absent(aggregate, "rust_analyzer")
absent(aggregate, "35%") -- No synthetic aggregate while a client has no percent.
progress.update(8002, "init", { kind = "report", percentage = 55 }, "rust_analyzer")
contains(display(), "45%")
progress.update(8001, "extra", { kind = "begin", percentage = 95 }, "lua_ls")
contains(display(), "60%") -- Average 65% (lua_ls) and 55% (rust_analyzer).
progress.update(8001, "extra", { kind = "end" }, "lua_ls")
contains(display(), "45%")
progress.update(8001, "index", { kind = "begin" }, "lua_ls")
absent(display(), "45%") -- A fresh begin must not reuse the prior 35%.
progress.update(8001, "index", { kind = "report", percentage = 35 }, "lua_ls")

-- Progress is scoped by client AND token. Reused string/number tokens do not
-- overwrite each other, and one client with several tasks counts only once.
progress.update(8001, 1, { kind = "begin", percentage = 10 }, "lua_ls")
progress.update(8001, "1", { kind = "begin", percentage = 20 }, "lua_ls")
assert(progress.current().count == 2)
progress.update(8001, 1, { kind = "end" }, "lua_ls")
progress.update(8001, "1", { kind = "end" }, "lua_ls")
progress.update(8001, "index", { kind = "end" }, "lua_ls")
local remaining = display()
contains(remaining, "55%")
contains(remaining, "rust_analyzer")
absent(remaining, "LSPs loading")

progress.update(8002, "init", { kind = "end" }, "rust_analyzer")
assert(progress.current() == nil and display() == "", "end must immediately remove indicator")

progress.update(8003, 3, { kind = "report", percentage = 220 }, "clangd")
contains(display(), "100%")
progress.update(8003, 3, { kind = "end" }, "clangd")

-- Verify wiring uses Neovim's actual LspProgress event and its client ID.
local original_lookup = vim.lsp.get_client_by_id
local event_ok, event_err = pcall(function()
  vim.lsp.get_client_by_id = function(id)
    if id == 8004 then
      return { id = id, name = "typescript-language-server" }
    end
    return original_lookup(id)
  end
  vim.api.nvim_exec_autocmds("LspProgress", {
    pattern = "begin",
    data = { client_id = 8004, params = { token = "starting", value = { kind = "begin" } } },
  })
  contains(display(), "typescript-language")
  contains(display(), "…") -- Long server names stay within 24 display cells.
  vim.api.nvim_exec_autocmds("LspProgress", {
    pattern = "end",
    data = { client_id = 8004, params = { token = "starting", value = { kind = "end" } } },
  })
  assert(display() == "")
end)
vim.lsp.get_client_by_id = original_lookup
progress.clear()
assert(event_ok, tostring(event_err))

for _, group in ipairs({ "StlLspSpinner", "StlLspProgress", "StlLspName" }) do
  assert(next(vim.api.nvim_get_hl(0, { name = group, link = false })) ~= nil,
    "missing compact LSP highlight group: " .. group)
end
print("LSP statusline progress regressions passed")
