if vim.g.loaded_phenix_color_preview then
  return
end
vim.g.loaded_phenix_color_preview = true

vim.keymap.set("n", "<Plug>(phenix-color-preview-toggle)", function()
  require("phenix.color_preview").toggle()
end, { desc = "Phenix: toggle color preview" })
