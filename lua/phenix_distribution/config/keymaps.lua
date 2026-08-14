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

for _, mapping in ipairs({
  { "<leader>p", "<Plug>(phenix-toggle)", "Phenix: toggle harness" },
  { "<leader>pf", "<Plug>(phenix-open-fullscreen)", "Phenix: open fullscreen harness" },
  { "<leader>pt", "<Plug>(phenix-open-fullscreen-tab)", "Phenix: open harness in tab" },
  { "<leader>pm", "<Plug>(phenix-maximize)", "Phenix: maximize prompt" },
  { "<leader>pi", "<Plug>(phenix-toggle-info)", "Phenix: toggle session info" },
  { "<leader>pr", "<Plug>(phenix-restore)", "Phenix: restore session" },
  { "<leader>ps", "<Plug>(phenix-select-transcript)", "Phenix: select transcript" },
  { "<leader>po", "<Plug>(phenix-select-model)", "Phenix: select model or routing" },
  { "<leader>pa", "<Plug>(phenix-authenticate)", "Phenix: authenticate provider" },
  { "<leader>pc", "<Plug>(phenix-cancel)", "Phenix: cancel response" },
}) do
  vim.keymap.set("n", mapping[1], mapping[2], { desc = mapping[3], remap = true })
end
