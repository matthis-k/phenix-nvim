if vim.g.loaded_phenix_distribution then
  return
end
vim.g.loaded_phenix_distribution = true

require("phenix_distribution.config.options")

-- Shared frontend primitives must not depend on a concrete UI backend.
vim.cmd.packadd("phenix-ui")

-- Configure the concrete shared frontend backend before feature wrappers bind
-- their typed interfaces to it.
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

require("phenix.color_preview").configure({
  border = require("constants").wins.border,
  palette = function()
    return require("base16-colorscheme").colors
  end,
})
require("phenix.frontend").provide("color_preview", require("phenix.color_preview"))
