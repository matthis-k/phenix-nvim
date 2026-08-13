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

return M
