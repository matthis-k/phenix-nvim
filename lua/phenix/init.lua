local Session = require("phenix.session")

local M = {}

local defaults = {
  keymap = "<leader>pp",
  width = 0.5,
  input_height = 0.25,
  input_height_min = 4,
  input_height_max = 12,
  follow_up_height = 0.25,
  follow_up_height_min = 4,
  follow_up_height_max = 12,
  fullscreen = false,
  tab = false,
}
local session = nil
local mapped_key = nil
local phenix_mapped_keys = {}

local function map_toggle(lhs)
  if mapped_key and mapped_key ~= lhs then
    pcall(vim.keymap.del, "n", mapped_key)
    mapped_key = nil
  end
  if not lhs or lhs == false or mapped_key == lhs then
    return
  end

  vim.keymap.set("n", lhs, "<Plug>(phenix-toggle)", { desc = "Phenix: toggle UI", remap = true })
  mapped_key = lhs
end

local function map_phenix_keymaps()
  for _, lhs in ipairs(phenix_mapped_keys) do
    pcall(vim.keymap.del, "n", lhs)
  end
  phenix_mapped_keys = { "<leader>p", "<leader>pf", "<leader>pt", "<leader>pm" }

  vim.keymap.set("n", "<leader>p", "<nop>", { desc = "Phenix" })
  vim.keymap.set("n", "<leader>pf", "<Plug>(phenix-open-fullscreen)", { desc = "Phenix: open fullscreen UI", remap = true })
  vim.keymap.set("n", "<leader>pt", "<Plug>(phenix-open-fullscreen-tab)", { desc = "Phenix: open fullscreen UI in tab", remap = true })
  vim.keymap.set("n", "<leader>pm", "<Plug>(phenix-maximize)", { desc = "Phenix: toggle prompt maximize", remap = true })
end

function M.setup(options)
  defaults = vim.tbl_deep_extend("force", {}, defaults, options or {})
  map_toggle(defaults.keymap)
  map_phenix_keymaps()
end

function M.toggle(options)
  if session and not session.closed then
    session:toggle_ui(options)
    return session
  end

  local merged = vim.tbl_deep_extend("force", {}, defaults, options or {})
  session = Session.new(merged)
  session:start()
  return session
end

function M.maximize()
  if session and not session.closed then
    session:toggle_maximize_input()
    return session
  end
  return nil
end

function M.current()
  if session and not session.closed then
    return session
  end
  return nil
end

function M.shutdown()
  if not session then
    return
  end
  local current = session
  session = nil
  current:shutdown()
end

function M._register_mappings()
  vim.keymap.set("n", "<Plug>(phenix-toggle)", M.toggle, { desc = "Phenix: toggle UI" })
  vim.keymap.set("n", "<Plug>(phenix-open-fullscreen)", function()
    M.toggle({ fullscreen = true })
  end, { desc = "Phenix: open fullscreen UI" })
  vim.keymap.set("n", "<Plug>(phenix-open-fullscreen-tab)", function()
    M.toggle({ tab = true, fullscreen = true })
  end, { desc = "Phenix: open fullscreen UI in tab" })
  vim.keymap.set("n", "<Plug>(phenix-maximize)", M.maximize, { desc = "Phenix: toggle prompt maximize" })
  vim.keymap.set("n", "<Plug>(phenix-shutdown)", M.shutdown, { desc = "Phenix: shut down session" })
end

function M._register_shutdown()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("PhenixNvimShutdown", { clear = true }),
    callback = function()
      if session then
        local current = session
        session = nil
        current:shutdown(false)
      end
    end,
  })
end

return M
