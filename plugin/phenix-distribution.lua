if vim.g.loaded_phenix_distribution then
  return
end
vim.g.loaded_phenix_distribution = true

require("phenix_distribution.config.options")

-- Configure shared Neovim plugins before loading feature modules.
require("phenix_distribution.config.snacks")

for _, package in ipairs({
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

local color_preview = require("phenix.color_preview")
local color_preview_config = {
  border = require("constants").wins.border,
  palette = function()
    return require("base16-colorscheme").colors
  end,
}
color_preview.configure(color_preview_config)
