local Snacks = require("snacks")
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
  disable = { bt = {}, ft = {} },
})

---@param action PhenixKeymapAction
---@return function
local function resolve(action)
  return function()
    local feature = require(action.module)
    local method = feature[action.method]
    if type(method) ~= "function" then
      error(string.format("Phenix API %s has no method %s", action.module, action.method))
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

