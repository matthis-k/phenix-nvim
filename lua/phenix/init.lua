local Settings = require("phenix.settings")

local M = {}
local session = nil

---@param options? PhenixOptions
---@return PhenixSettings
function M.setup(options)
  local settings = Settings.configure(options)
  local mappings = require("phenix.mappings")
  mappings.install_default_mappings()
  mappings.install_default_mapping(settings.keymap, "<Plug>(phenix-toggle)", "Phenix: toggle UI")
  return settings
end

---@param options? PhenixOptions
---@return Phenix.Session
function M.toggle(options)
  if session and not session.closed then
    session:toggle_ui(options)
    return session
  end

  local merged = Settings.merge(options)
  session = require("phenix.session").new(merged)
  session:start()
  return session
end

---@return Phenix.Session|nil
function M.maximize()
  if session and not session.closed then
    session:toggle_maximize_input()
    return session
  end
  return nil
end

---@return boolean
function M.cancel()
  return session ~= nil and not session.closed and session:cancel() or false
end

---@return Phenix.Session|nil
function M.current()
  if session and not session.closed then
    return session
  end
  return nil
end

function M.shutdown()
  if not session then
    return
  end
  local current = session
  session = nil
  current:shutdown()
end

function M._shutdown_for_exit()
  if not session then
    return
  end
  local current = session
  session = nil
  current:shutdown(false)
end

return M
