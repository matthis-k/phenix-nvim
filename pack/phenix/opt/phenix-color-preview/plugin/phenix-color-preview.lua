if vim.g.loaded_phenix_color_preview then
  return
end
vim.g.loaded_phenix_color_preview = true

local feature = require("phenix.color_preview")
require("phenix.frontend").register_api("color_preview", feature)

vim.keymap.set("n", "<Plug>(phenix-color-preview-toggle)", feature.toggle, {
  desc = "Phenix: toggle color preview",
})
