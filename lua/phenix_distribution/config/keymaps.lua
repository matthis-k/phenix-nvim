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

---@param action PhenixKeymapAction
---@return function
local function resolve(action)
  return function()
    local api = Frontend.require_api(action.api)
    local method = api[action.method]
    if type(method) ~= "function" then
      error(string.format("Phenix API %s has no method %s", action.api, action.method))
    end
    if action.args ~= nil then
      return method(vim.deepcopy(action.args))
    end
    return method()
  end
end

for _, mapping in ipairs(keymaps.maps or {}) do
  local rhs = mapping.action and resolve(mapping.action) or mapping.rhs
  assert(rhs ~= nil, "keymap must define rhs or action: " .. tostring(mapping.lhs))
  Snacks.keymap.set(mapping.mode, mapping.lhs, rhs, mapping.opts)
end

local phenix_maps = {
  { "n", "<leader>p", "<nop>", "Phenix AI" },
  { "n", "<leader>pp", "<cmd>Phenix toggle<cr>", "Phenix: toggle sidebar" },
  { "n", "<leader>pr", "<cmd>Phenix reference<cr>", "Phenix: add reference" },
  { "x", "<leader>pr", ":Phenix reference<cr>", "Phenix: add reference" },
  { "n", "<leader>pR", "<cmd>Phenix reference pick<cr>", "Phenix: pick reference" },
  { "n", "<leader>ps", "<cmd>Phenix send<cr>", "Phenix: send prompt" },
  { "n", "<leader>pc", "<cmd>Phenix cancel<cr>", "Phenix: cancel response" },
  { "n", "<leader>pn", "<cmd>Phenix session new<cr>", "Phenix: new session" },
  { "n", "<leader>px", "<cmd>Phenix session close<cr>", "Phenix: close session" },
  { "n", "<leader>pS", "<cmd>Phenix session select<cr>", "Phenix: choose session" },
  { "n", "<leader>pa", "<cmd>Phenix auth<cr>", "Phenix: authenticate provider" },
  { "n", "<leader>pm", "<cmd>Phenix select<cr>", "Phenix: choose model / routing" },
  { "n", "<leader>pi", "<cmd>Phenix image<cr>", "Phenix: attach image" },
}

for _, mapping in ipairs(phenix_maps) do
  vim.keymap.set(mapping[1], mapping[2], mapping[3], { desc = mapping[4] })
end
