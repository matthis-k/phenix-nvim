if vim.g.loaded_phenix_distribution_late then
  return
end
vim.g.loaded_phenix_distribution_late = true

-- Integration policy runs after normal plugin entrypoints have been sourced.
-- Keep this order explicit rather than relying on runtimepath/package ordering.
require("phenix_distribution.config.session")
require("phenix_distribution.config.snacks")
require("phenix_distribution.config.keymaps")
require("phenix_distribution.config.git")
require("phenix_distribution.config.lsp")
require("phenix_distribution.config.completion")
require("phenix_distribution.config.opencode")
require("phenix_distribution.bars")
