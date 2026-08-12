if vim.g.loaded_phenix_distribution_late then
  return
end
vim.g.loaded_phenix_distribution_late = true

-- User policy is deliberately last. Feature packages initialize themselves and
-- publish typed interfaces; the distribution only chooses mappings/composition.
require("phenix_distribution.config.keymaps")
