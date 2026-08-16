local Settings = require("phenix.settings")
local Frontend = require("phenix.frontend")

---@class PhenixFrontend
local M = {}
local session = nil

local function state()
  return Frontend.state("agent")
end

---@param options? PhenixOptions
---@return PhenixSettings
function M.setup(options)
  local settings = Settings.configure(options)
  local config = Frontend.config("agent")
  for key in pairs(config) do
    config[key] = nil
  end
  for key, value in pairs(settings) do
    config[key] = value
  end
  return settings
end

---@param options? PhenixOptions
---@return Phenix.Session
function M.toggle(options)
  if session and not session.closed then
    session:toggle_ui(options)
    return session
  end

  session = require("phenix.session").new(Settings.merge(options))
  state().session = session
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
function M.toggle_info()
  return session ~= nil and not session.closed and session:toggle_info() or false
end

---@return boolean
function M.restore()
  return session ~= nil and not session.closed and session:restore() or false
end

---@return boolean
function M.select_transcript()
  return session ~= nil and not session.closed and session:select_transcript() or false
end

---@return boolean
function M.select_model()
  return session ~= nil and not session.closed and session:select_model() or false
end

---@return boolean
function M.authenticate()
  return session ~= nil and not session.closed and session:authenticate() or false
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
  state().session = nil
  current:shutdown()
end

function M._shutdown_for_exit()
  if not session then
    return
  end
  local current = session
  session = nil
  state().session = nil
  current:shutdown(false)
end

return M
