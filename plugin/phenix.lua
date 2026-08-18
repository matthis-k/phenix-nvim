if vim.g.loaded_phenix then
  return
end
vim.g.loaded_phenix = 1

require("phenix.mappings").install_plug_mappings()
require("phenix.frontend").project_api("agent", require("phenix"))

local group = vim.api.nvim_create_augroup("Phenix", { clear = true })
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    require("phenix.markdown").prepare_window(args.buf, vim.api.nvim_get_current_win())
  end,
  desc = "Phenix: prepare transcript windows for Markview",
})
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    local loaded = package.loaded.phenix
    if loaded then
      loaded._shutdown_for_exit()
    end
  end,
  desc = "Phenix: shut down active conductor session",
})
