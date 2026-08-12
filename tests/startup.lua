local function shutdown()
  local ok, phenix = pcall(require, "phenix")
  if ok then
    pcall(phenix.shutdown)
  end
end

local ok, error_value = xpcall(function()
  local config_directory = require("nix-info").settings.config_directory
  assert(type(config_directory) == "string", "nix wrapper config_directory was not serialized as a string")

  assert(vim.o.statusline == "%!v:lua.Ui.StatusLine()", "custom statusline was not loaded")
  assert(vim.o.tabline == "%!v:lua.Ui.TabLine()", "custom tabline was not loaded")
  assert(vim.o.statuscolumn == "%!v:lua.Ui.StatusColumn()", "custom statuscolumn was not loaded")
  assert(
    type(_G.Ui.StatusLine) == "function"
      and type(_G.Ui.TabLine) == "function"
      and type(_G.Ui.StatusColumn) == "function",
    "custom UI functions were not initialized"
  )

  local phenix = require("phenix")
  phenix.toggle()
  assert(vim.wait(15000, function()
    local session = phenix.current()
    return session and session:is_ready()
  end, 50), "Phenix standard ACP session did not become ready")

  local session = assert(phenix.current(), "Phenix session disappeared after becoming ready")
  assert(session.session_id and session.root_node_id, "standard ACP session was not initialized")
  assert(
    vim.api.nvim_win_get_width(session.ui.transcript_window) > 48,
    "Phenix sidebar did not use the wider default width"
  )
  local process = assert(session.client.process, "ACP process is not running")

  phenix.toggle()
  assert(not session.ui:is_visible(), "sidebar did not hide")
  assert(session.client.process == process and not session.client.stopped, "ACP process stopped while sidebar was hidden")

  phenix.toggle()
  assert(session.ui:is_visible(), "sidebar did not reopen")
  assert(session.client.process == process and not session.client.stopped, "ACP process restarted while toggling sidebar")
end, debug.traceback)

shutdown()

if not ok then
  io.stderr:write(error_value .. "\n")
  vim.cmd("cquit 1")
end

vim.cmd("qa!")
