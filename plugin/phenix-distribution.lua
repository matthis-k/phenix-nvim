if vim.g.loaded_phenix_distribution then
  return
end
vim.g.loaded_phenix_distribution = true

-- Mechanisms initialize themselves; the distribution only selects and configures
-- them. Core Neovim policy is applied before normal plugin integration.
vim.cmd.packadd("phenix-bars")
vim.cmd.packadd("phenix-color-preview")

require("phenix_distribution.config.options")
require("phenix_distribution.config.theme")

require("phenix.color_preview").configure({
  border = require("constants").wins.border,
  palette = function()
    return require("base16-colorscheme").colors
  end,
})
