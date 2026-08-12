if vim.g.loaded_phenix_ui then
  return
end
vim.g.loaded_phenix_ui = true

-- Keep the shared frontend layer implementation-agnostic. Feature plugins
-- extend Phenix.api, Phenix.config, and Phenix.state through this runtime;
-- concrete backends (Snacks, Resession, etc.) remain integration details.
require("phenix.frontend").global()
