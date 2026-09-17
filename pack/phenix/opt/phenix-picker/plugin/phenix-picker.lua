if vim.g.loaded_phenix_picker then
  return
end
vim.g.loaded_phenix_picker = true

require("phenix.frontend").project_api("picker", require("phenix.features.picker"))
