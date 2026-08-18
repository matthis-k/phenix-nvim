local Settings = require("phenix.settings")
local Frontend = require("phenix.frontend")
local Conductor = require("phenix.conductor")

---@class PhenixFrontend
local M = {}
local session = nil

local function current_session()
  if session and not session.closed then
    return session
  end
  return nil
end

---@param options? PhenixOptions
---@return PhenixSettings
function M.setup(options)
  local settings = Settings.configure(options)
  Frontend.project_config("agent", settings)
  return settings
end

---@param options? PhenixOptions
---@return Phenix.Session
function M.toggle(options)
  if session and not session.closed then
    session:toggle_ui(options)
    return session
  end

  require("phenix.session_actions")
  local settings = Settings.merge(options)
  settings.configured_target = vim.deepcopy(settings.target)
  settings.target = options and vim.deepcopy(options.target) or nil
  session = require("phenix.session").new(settings)
  session:start()
  return session
end

---@return Phenix.Session|nil
function M.maximize()
  local current = current_session()
  if current then
    current:toggle_maximize_input()
  end
  return current
end

---@return boolean
function M.toggle_info()
  local current = current_session()
  return current ~= nil and current:toggle_info() or false
end

---@return boolean
function M.restore()
  local current = current_session()
  return current ~= nil and current:restore() or false
end

---@return boolean
function M.select_transcript()
  local current = current_session()
  return current ~= nil and current:select_transcript() or false
end

---@return boolean
function M.select_model()
  local current = current_session()
  return current ~= nil and current:select_model() or false
end

---@return boolean
function M.select_callable()
  local current = current_session()
  return current ~= nil and current:select_callable() or false
end

---@return boolean
function M.authenticate()
  local current = current_session()
  return current ~= nil and current:authenticate() or false
end

---@return boolean
function M.cancel()
  local current = current_session()
  return current ~= nil and current:cancel() or false
end

---@return table|nil
function M.state()
  local current = current_session()
  return current and current:state() or nil
end

---@return table[]
function M.callables()
  local current = current_session()
  return current and current:callables() or {}
end

---@param callable_id string
---@param objective string
---@param callback? function
---@return boolean
function M.run_callable(callable_id, objective, callback)
  local current = current_session()
  return current ~= nil and current:run_callable(callable_id, objective, callback) or false
end

---@param callback? function
---@return boolean
function M.refresh_callables(callback)
  local current = current_session()
  return current ~= nil and current:refresh_callables(callback) or false
end

---@param name? string
---@param callback? function
---@return boolean
function M.fork(name, callback)
  local current = current_session()
  return current ~= nil and current:fork(name, callback) or false
end

---@param name? string
---@param callback? function
---@return boolean
function M.rename(name, callback)
  local current = current_session()
  if not current then
    return false
  end
  if name ~= nil then
    return current:rename(name, callback)
  end
  local summary = current:state() and current:state().session or nil
  vim.ui.input({
    prompt = "Rename Phenix session",
    default = summary and (summary.name or summary.id) or "",
  }, function(value)
    if value ~= nil and vim.trim(value) ~= "" then
      current:rename(value, callback)
    end
  end)
  return true
end

---@param target table
---@param callback? function
---@return boolean
function M.set_target(target, callback)
  local current = current_session()
  return current ~= nil and current:set_target(target, callback) or false
end

---@param backend_id string
---@param callback? function
---@return boolean
function M.refresh_backend(backend_id, callback)
  local current = current_session()
  return current ~= nil and current:refresh_backend(backend_id, callback) or false
end

---@param callback? function
---@return boolean
function M.refresh_catalogs(callback)
  local current = current_session()
  return current ~= nil and current:refresh_catalogs(callback) or false
end

function M.fixed_target(backend, provider, model, inference)
  return Conductor.fixed_target(backend, provider, model, inference)
end

function M.routed_target(profile)
  return Conductor.routed_target(profile)
end

---@return Phenix.Session|nil
function M.current()
  return current_session()
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
