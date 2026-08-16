if vim.g.loaded_phenix_callable_actions == 1 then
  return
end
vim.g.loaded_phenix_callable_actions = 1

local function frontend()
  return require("phenix")
end

vim.keymap.set("n", "<Plug>(phenix-select-callable)", function()
  frontend().select_callable()
end, {
  silent = true,
  desc = "Select Phenix callable",
})

vim.keymap.set("n", "<Plug>(phenix-refresh-callables)", function()
  frontend().refresh_callables()
end, {
  silent = true,
  desc = "Refresh Phenix callable catalog",
})
