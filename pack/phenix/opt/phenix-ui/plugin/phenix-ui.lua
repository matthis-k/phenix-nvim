if vim.g.loaded_phenix_ui then
  return
end
vim.g.loaded_phenix_ui = true

local Frontend = require("phenix.frontend")
Frontend.project_api("ui", {
  window = require("phenix.frontend.window"),
})
