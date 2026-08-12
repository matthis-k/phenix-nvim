local Snacks = require("snacks")
local Frontend = require("phenix.frontend")
local keymaps = require("keymaps")
vim.g.mapleader = keymaps.leader
vim.g.maplocalleader = keymaps.leader

require("which-key").setup({
  delay = 0,
  expand = 1,
  preset = "classic",
  icons = { breadcrumb = "»", separator = "➜", group = "+" },
  win = {
    border = require("constants").wins.border,
    wo = { winblend = 0 },
  },
  layout = { height = { min = 4, max = 25 }, width = { min = 20, max = 50 }, spacing = 3, align = "center" },
  show_help = false,
  show_keys = true,
  triggers = { { "<auto>", mode = "nixsoc" } },
  disable = { buftypes = {}, filetypes = {} },
})

local function call(name, method)
  return function(...)
    local interface = Frontend.interface(name)
    return interface[method](...)
  end
end

local picker = {
  ["<leader><leader>"] = "smart",
  ["<leader>bb"] = "buffers",
  ["<leader>bl"] = "buffers",
  ["<leader>/"] = "grep",
  ["<leader>:"] = "command_history",
  ["<leader>fD"] = "diagnostics_buffer",
  ["<leader>fd"] = "diagnostics",
  ["<leader>fb"] = "buffers",
  ["<leader>ff"] = "files",
  ["<leader>fg"] = "git_files",
  ["<leader>fl"] = "lines",
  ["<leader>fm"] = "marks",
  ["<leader>fp"] = "projects",
  ["<leader>fR"] = "rename_file",
  ["<leader>fr"] = "recent",
  ["<leader>fW"] = "grep_word",
  ["<leader>fw"] = "grep",
  ["<leader>sa"] = "autocmds",
  ["<leader>sc"] = "commands",
  ["<leader>sH"] = "highlights",
  ["<leader>sh"] = "help",
  ["<leader>si"] = "icons",
  ["<leader>sk"] = "keymaps",
  ["<leader>sm"] = "man",
  ["<leader>gs"] = "git_status",
  ["<leader>gb"] = "git_branches",
  ["<leader>gl"] = "git_log",
  ["<leader>gL"] = "git_log_line",
  ["<leader>gd"] = "git_diff",
  ["<leader>gS"] = "git_stash",
  ["<leader>gi"] = "gh_issue",
  ["<leader>gI"] = "gh_issue",
  ["<leader>gp"] = "gh_pr",
  ["<leader>gP"] = "gh_pr",
  ["gd"] = "lsp_definitions",
  ["gri"] = "lsp_implementations",
  ["grr"] = "lsp_references",
  ["grd"] = "lsp_type_definitions",
}

for _, km in ipairs(keymaps.maps or {}) do
  -- OpenCode is no longer part of the distribution; Phenix ACP owns the harness UX.
  if km.lhs ~= "<leader>o" then
    local replacement = picker[km.lhs]
    if replacement then
      km = vim.deepcopy(km)
      km.rhs = call("picker", replacement)
      if km.lhs == "<leader>gI" or km.lhs == "<leader>gP" then
        local method = replacement
        km.rhs = function()
          return Frontend.interface("picker")[method]({ state = "all" })
        end
      end
    elseif km.lhs == "<leader>t" then
      km = vim.deepcopy(km)
      km.rhs = call("terminal", "toggle")
    elseif km.lhs == "<leader>n" then
      km = vim.deepcopy(km)
      km.rhs = call("notifier", "history")
    elseif km.lhs == "<leader><esc>" then
      km = vim.deepcopy(km)
      km.rhs = call("notifier", "hide")
    elseif km.lhs == "<leader>e" then
      km = vim.deepcopy(km)
      km.rhs = call("explorer", "open")
    elseif km.lhs == "<leader>vd" then
      km = vim.deepcopy(km)
      km.rhs = call("dashboard", "open")
    elseif km.lhs == "<leader>vs" then
      km = vim.deepcopy(km)
      km.rhs = call("session", "pick")
    end
    Snacks.keymap.set(km.mode, km.lhs, km.rhs, km.opts)
  end
end

for _, mapping in ipairs({
  { "<leader>p", "<Plug>(phenix-toggle)", "Phenix: toggle harness" },
  { "<leader>pf", "<Plug>(phenix-open-fullscreen)", "Phenix: open fullscreen harness" },
  { "<leader>pt", "<Plug>(phenix-open-fullscreen-tab)", "Phenix: open harness in tab" },
  { "<leader>pm", "<Plug>(phenix-maximize)", "Phenix: maximize prompt" },
  { "<leader>pc", "<Plug>(phenix-cancel)", "Phenix: cancel response" },
}) do
  vim.keymap.set("n", mapping[1], mapping[2], { desc = mapping[3], remap = true })
end
