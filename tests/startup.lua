local function shutdown()
  local ok, phenix = pcall(require, "phenix")
  if ok then
    pcall(phenix.shutdown)
  end
end

local ok, error_value = xpcall(function()
  local config_directory = require("nix-info").settings.config_directory
  assert(type(config_directory) == "string", "nix wrapper config_directory was not serialized as a string")

  -- A UI/integration callback must not be able to abort JSON frame consumption.
  -- Losing a later prompt response from the same stdout chunk leaves the session
  -- permanently `prompting`, which presents exactly like an unreactive ACP session.
  local transport_errors = {}
  local response_after_handler_error = false
  local transport = require("phenix.acp").new({
    on_notification = function(method)
      if method == "test/handler-error" then
        error("intentional handler failure")
      end
    end,
    on_stderr = function(message)
      transport_errors[#transport_errors + 1] = message
    end,
  })
  transport.pending[41] = function(result)
    response_after_handler_error = result and result.ok == true
  end
  transport:_consume_stdout(
    vim.json.encode({ jsonrpc = "2.0", method = "test/handler-error", params = {} })
      .. "\n"
      .. vim.json.encode({ jsonrpc = "2.0", id = 41, result = { ok = true } })
      .. "\n"
  )
  assert(response_after_handler_error, "ACP handler failure discarded a later response frame")
  assert(#transport_errors == 1, "ACP handler failure was not isolated and reported exactly once")

  local bar_expression = "%!v:lua.PhenixBars.render('%s')"
  assert(vim.o.statusline == bar_expression:format("statusline"), "custom statusline was not loaded through phenix.bars")
  assert(vim.o.tabline == bar_expression:format("tabline"), "custom tabline was not loaded through phenix.bars")
  assert(vim.o.statuscolumn == bar_expression:format("statuscolumn"), "custom statuscolumn was not loaded through phenix.bars")
  assert(type(_G.PhenixBars) == "table" and type(_G.PhenixBars.render) == "function", "phenix.bars was not initialized")

  local bars = require("phenix.bars")
  assert(type(bars.configure) == "function" and type(bars.render_part) == "function", "phenix.bars public API is incomplete")
  assert(bars.render("statusline") ~= "", "configured statusline rendered empty")

  local preview_map = vim.fn.maparg("<Plug>(phenix-color-preview-toggle)", "n", false, true)
  assert(preview_map.lhs ~= "", "color preview did not expose its <Plug> mapping")
  assert(type(require("phenix.color_preview").configure) == "function", "color preview configuration API is unavailable")

  local cancel_plug = vim.fn.maparg("<Plug>(phenix-cancel)", "n", false, true)
  assert(cancel_plug.lhs ~= "", "Phenix frontend did not expose a cancel <Plug> action")
  assert(
    vim.fn.maparg(" pc", "n", false, true).rhs == "<Plug>(phenix-cancel)",
    "default Phenix cancel mapping does not use the public <Plug> action"
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
