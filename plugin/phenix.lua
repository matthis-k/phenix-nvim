if vim.g.loaded_phenix then
  return
end
vim.g.loaded_phenix = 1

require("phenix.mappings").install_plug_mappings()
local frontend = require("phenix.frontend")
frontend.register_api("agent", require("phenix"), {
  contract = {
    setup = "function",
    toggle = "function",
    maximize = "function",
    cancel = "function",
    toggle_info = "function",
    restore = "function",
    select_transcript = "function",
    select_model = "function",
    select_callable = "function",
    authenticate = "function",
    state = "function",
    fork = "function",
    rename = "function",
    set_target = "function",
    refresh_backend = "function",
    refresh_catalogs = "function",
    refresh_callables = "function",
    callables = "function",
    run_callable = "function",
    fixed_target = "function",
    routed_target = "function",
    current = "function",
    shutdown = "function",
  },
})

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
