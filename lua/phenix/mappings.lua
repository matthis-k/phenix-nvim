local M = {}

local actions = {
  ["<Plug>(phenix-toggle)"] = { "toggle", "Phenix: toggle UI" },
  ["<Plug>(phenix-open-fullscreen)"] = { "fullscreen", "Phenix: open fullscreen UI" },
  ["<Plug>(phenix-open-fullscreen-tab)"] = { "tab", "Phenix: open fullscreen UI in tab" },
  ["<Plug>(phenix-maximize)"] = { "maximize", "Phenix: toggle prompt maximize" },
  ["<Plug>(phenix-cancel)"] = { "cancel", "Phenix: cancel current response" },
  ["<Plug>(phenix-shutdown)"] = { "shutdown", "Phenix: shut down session" },
}

local function invoke(action)
  local phenix = require("phenix")
  if action == "fullscreen" then
    phenix.toggle({ fullscreen = true })
  elseif action == "tab" then
    phenix.toggle({ tab = true, fullscreen = true })
  else
    phenix[action]()
  end
end

function M.install_plug_mappings()
  for lhs, action in pairs(actions) do
    vim.keymap.set("n", lhs, function()
      invoke(action[1])
    end, { desc = action[2] })
  end
end

---@param lhs string|false|nil
---@param rhs string
---@param description string
function M.install_default_mapping(lhs, rhs, description)
  if not lhs or lhs == false then
    return
  end
  local existing = vim.fn.maparg(lhs, "n", false, true)
  if existing.lhs and existing.lhs ~= "" then
    return
  end
  vim.keymap.set("n", lhs, rhs, { desc = description, remap = true })
end

function M.install_default_mappings()
  M.install_default_mapping("<leader>p", "<Plug>(phenix-toggle)", "Phenix: toggle UI")
  M.install_default_mapping("<leader>pf", "<Plug>(phenix-open-fullscreen)", "Phenix: open fullscreen UI")
  M.install_default_mapping("<leader>pt", "<Plug>(phenix-open-fullscreen-tab)", "Phenix: open fullscreen UI in tab")
  M.install_default_mapping("<leader>pm", "<Plug>(phenix-maximize)", "Phenix: toggle prompt maximize")
  M.install_default_mapping("<leader>pc", "<Plug>(phenix-cancel)", "Phenix: cancel current response")
end

return M
