local Settings = require("phenix.settings")
local Frontend = require("phenix.frontend")

---@class PhenixAcpFrontend
local M = {}
local session = nil

local function state()
  return Frontend.state("acp")
end

---@param options? PhenixOptions
---@return PhenixSettings
function M.setup(options)
  local settings = Settings.configure(options)
  local config = Frontend.config("acp")
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

  local merged = Settings.merge(options)
  session = require("phenix.session").new(merged)
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

function M.restore()
  if session and not session.closed then
    session:restore()
  end
end

function M.select_transcript()
  if session and not session.closed then
    session:select_transcript()
  end
end

---@return { id: string, title: string }[]
function M.workflows()
  return session and not session.closed and session:workflow_definitions() or {}
end

---@param workflow_id string
---@param objective string
---@param difficulty? "d0"|"d1"|"d2"|"d3"|"d4"
---@return boolean
function M.start_workflow(workflow_id, objective, difficulty)
  return session ~= nil and not session.closed and session:start_workflow(workflow_id, objective, difficulty) or false
end

---@param role string
---@param objective string
---@param difficulty? "d0"|"d1"|"d2"|"d3"|"d4"
---@param parent_node? string
---@return boolean
function M.delegate(role, objective, difficulty, parent_node)
  return session ~= nil and not session.closed and session:delegate(role, objective, difficulty, parent_node) or false
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
