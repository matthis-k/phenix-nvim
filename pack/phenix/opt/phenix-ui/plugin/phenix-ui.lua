if vim.g.loaded_phenix_ui then
  return
end
vim.g.loaded_phenix_ui = true

-- Keep the shared frontend layer implementation-agnostic. Feature backends
-- (Snacks, Resession, etc.) are configured by the distribution/integration
-- layer and publish implementations through this registry.
require("phenix.frontend").global()
