---@type PhenixPicker
local M = {}

-- Declare the distribution's supported picker methods explicitly. A dynamic
-- __index returned a function for *any* typo, defeating keymap validation.
local sources = {
  "autocmds",
  "buffers",
  "command_history",
  "commands",
  "diagnostics",
  "diagnostics_buffer",
  "files",
  "gh_issue",
  "gh_pr",
  "git_branches",
  "git_diff",
  "git_files",
  "git_log",
  "git_log_line",
  "git_stash",
  "git_status",
  "grep",
  "grep_word",
  "help",
  "highlights",
  "icons",
  "keymaps",
  "lines",
  "lsp_definitions",
  "lsp_implementations",
  "lsp_references",
  "lsp_type_definitions",
  "man",
  "marks",
  "projects",
  "recent",
  "smart"
}

function M.open(name, opts)
  local source = require("snacks").picker[name]
  if type(source) ~= "function" then
    error("Snacks picker source is unavailable: " .. tostring(name))
  end
  return source(opts)
end

for _, name in ipairs(sources) do
  local source_name = name
  M[source_name] = function(opts)
    return M.open(source_name, opts)
  end
end

function M.rename_file(opts)
  return require("snacks").rename.rename_file(opts)
end

return M
