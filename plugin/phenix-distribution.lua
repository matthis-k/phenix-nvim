if vim.g.loaded_phenix_distribution then
  return
end
vim.g.loaded_phenix_distribution = true

-- Only behavior owned by this repository is packaged. The rest of the editor
-- runtime is configuration of Neovim and third-party plugins.
vim.cmd.packadd("phenix-bars")
vim.cmd.packadd("phenix-color-preview")

require("phenix.color_preview").configure({
  border = require("constants").wins.border,
})
require("phenix_distribution.bars")
