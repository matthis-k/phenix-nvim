if vim.g.loaded_phenix_acp then
  return
end
vim.g.loaded_phenix_acp = true

require("phenix.mappings").install_plug_mappings()
local frontend = require("phenix.frontend")
frontend.register_api("acp", require("phenix"), {
  contract = {
    setup = "function",
    toggle = "function",
    cancel = "function",
    toggle_info = "function",
    restore = "function",
    select_transcript = "function",
    configuration = "function",
    request = "function",
    workflows = "function",
    start_workflow = "function",
    delegate = "function",
    current = "function",
    shutdown = "function",
  },
})

local group = vim.api.nvim_create_augroup("PhenixAcp", { clear = true })
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    require("phenix.markdown").prepare_window(args.buf, vim.api.nvim_get_current_win())
  end,
  desc = "Phenix ACP: prepare transcript windows for Markview",
})
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    local loaded = package.loaded.phenix
    if loaded then
      loaded._shutdown_for_exit()
    end
  end,
  desc = "Phenix ACP: shut down active session",
})
