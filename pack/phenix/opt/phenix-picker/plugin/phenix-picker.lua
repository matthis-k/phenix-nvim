if vim.g.loaded_phenix_picker then
  return
end
vim.g.loaded_phenix_picker = true

require("phenix.frontend").register_api("picker", require("phenix.features.picker"), {
  contract = {
    files = "function",
    buffers = "function",
    grep = "function",
    lsp_definitions = "function",
  },
})
