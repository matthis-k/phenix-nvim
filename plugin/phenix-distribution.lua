if vim.g.loaded_phenix_distribution then
  return
end
vim.g.loaded_phenix_distribution = true

require("phenix_distribution.config.options")

-- Phenix is a collection of feature plugins. Load the shared frontend/runtime
-- first, then feature implementations that register typed interfaces into it.
for _, package in ipairs({
  "phenix-ui",
  "phenix-theme",
  "phenix-bars",
  "phenix-color-preview",
  "phenix-session",
  "phenix-picker",
  "phenix-dashboard",
  "phenix-explorer",
  "phenix-terminal",
  "phenix-notify",
  "phenix-git",
  "phenix-lsp",
  "phenix-completion",
}) do
  vim.cmd.packadd(package)
end

require("phenix.color_preview").configure({
  border = require("constants").wins.border,
  palette = function()
    return require("base16-colorscheme").colors
  end,
})
require("phenix.frontend").provide("color_preview", require("phenix.color_preview"))
require("phenix_distribution.bars")
require("phenix.frontend").provide("bars", require("phenix.bars"))
