local function shutdown()
  local ok, phenix = pcall(require, "phenix")
  if ok then
    pcall(phenix.shutdown)
  end
end

local function session_errors(session)
  if not session or not session.ui or type(session.ui.entries) ~= "table" then
    return ""
  end

  local errors = {}
  for _, entry in ipairs(session.ui.entries) do
    if entry.kind == "error" then
      errors[#errors + 1] = tostring(entry.text)
    end
  end
  return table.concat(errors, " | ")
end

local ok, error_value = xpcall(function()
  local config_directory = require("nix-info").settings.config_directory
  assert(type(config_directory) == "string", "nix wrapper config_directory was not serialized as a string")

  assert(type(_G.Phenix) == "table", "global Phenix registry was not initialized")
  assert(type(Phenix.config) == "table" and type(Phenix.state) == "table", "Phenix global config/state are unavailable")
  assert(type(Phenix.api) == "table" and type(Phenix.require_api) == "function", "Phenix API facade is unavailable")
  for _, name in ipairs({ "ui", "picker", "terminal", "notifier", "explorer", "dashboard", "session", "git", "lsp", "completion", "theme", "bars", "color_preview", "acp" }) do
    assert(Phenix.api[name] ~= nil, "missing Phenix feature API: " .. name)
    assert(Phenix.require_api(name) == Phenix.api[name], "Phenix API lookup does not resolve the public facade: " .. name)
    assert(type(Phenix.config[name]) == "table", "missing Phenix feature config: " .. name)
    assert(type(Phenix.state[name]) == "table", "missing Phenix feature state: " .. name)
  end
  assert(type(Phenix.api.ui.window.scratch) == "function", "shared UI facade does not expose window utilities")
  assert(vim.fn.maparg(" o", "n") == "", "OpenCode mapping survived removal")

  local transport_errors = {}
  local response_after_handler_error = false
  local transport = require("phenix.acp").new({
    on_notification = function(method)
      if method == "test/handler-error" then error("intentional handler failure") end
    end,
    on_stderr = function(message) transport_errors[#transport_errors + 1] = message end,
  })
  transport.pending[41] = function(result) response_after_handler_error = result and result.ok == true end
  transport:_consume_stdout(vim.json.encode({ jsonrpc = "2.0", method = "test/handler-error", params = {} }) .. "\n" .. vim.json.encode({ jsonrpc = "2.0", id = 41, result = { ok = true } }) .. "\n")
  assert(response_after_handler_error, "ACP handler failure discarded a later response frame")
  assert(#transport_errors == 1, "ACP handler failure was not isolated and reported exactly once")

  local bar_expression = "%%!v:lua.PhenixBars.render('%s')"
  assert(vim.o.statusline == bar_expression:format("statusline"), "custom statusline was not loaded through phenix.bars")
  assert(vim.o.tabline == bar_expression:format("tabline"), "custom tabline was not loaded through phenix.bars")
  assert(vim.o.statuscolumn == bar_expression:format("statuscolumn"), "custom statuscolumn was not loaded through phenix.bars")

  local preview_map = vim.fn.maparg("<Plug>(phenix-color-preview-toggle)", "n", false, true)
  assert(preview_map.lhs ~= "", "color preview did not expose its <Plug> mapping")
  local cancel_plug = vim.fn.maparg("<Plug>(phenix-cancel)", "n", false, true)
  assert(cancel_plug.lhs ~= "", "Phenix ACP frontend did not expose cancel")
  assert(vim.fn.maparg(" pc", "n", false, true).rhs == "<Plug>(phenix-cancel)", "distribution does not map through ACP public action")

  local phenix = Phenix.api.acp
  phenix.toggle()
  assert(vim.wait(15000, function()
    local session = phenix.current()
    return session and (session:is_ready() or session.client.stopped or session_errors(session) ~= "")
  end, 50), "Phenix standard ACP session did not become ready or terminate")

  local session = assert(phenix.current(), "Phenix session disappeared during startup")
  if not session:is_ready() then
    error("Phenix standard ACP session did not become ready: " .. session_errors(session))
  end
  assert(Phenix.state.acp.session == session, "ACP session was not projected into global Phenix state")
  assert(session.session_id and session.root_node_id, "standard ACP session was not initialized")
  assert(Phenix.config.acp.width == 0.5, "Phenix sidebar default width is not half the editor")
  local expected_width = math.floor(vim.o.columns * Phenix.config.acp.width)
  assert(
    vim.api.nvim_win_get_width(session.ui.transcript_window) >= expected_width - 1,
    "Phenix sidebar did not apply its proportional default width"
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
