if vim.g.loaded_phenix_ui then
  return
end
vim.g.loaded_phenix_ui = true

require("phenix.frontend").global()
require("phenix.frontend.snacks_config")
