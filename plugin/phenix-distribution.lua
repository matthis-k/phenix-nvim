if vim.g.loaded_phenix_distribution then
  return
end
vim.g.loaded_phenix_distribution = true

require("phenix_distribution.config.options")

-- phenix-ui is a declared wrapped dependency because phenix-acp consumes the
-- shared frontend facade during startup. Do not activate the in-tree optional
-- package here as well: one runtime must have one owner for each typed API.

-- Configure concrete shared backends before feature wrappers publish their APIs.
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

Phenix.config.color_preview.border = require("constants").wins.border
Phenix.config.color_preview.palette = function()
  return require("base16-colorscheme").colors
end
Phenix.api.color_preview.configure(Phenix.config.color_preview)
