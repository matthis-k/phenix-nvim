local Transport = require("phenix.transport")

local M = {}
local Client = {}
Client.__index = Client

local function nonempty(value, name)
  assert(type(value) == "string" and vim.trim(value) ~= "", name .. " must be a non-empty string")
  return value
end

local function finish(callback, result, err)
  if callback then
    vim.schedule(function()
      callback(result, err)
    end)
  end
end

function M.fixed_target(backend, provider, model, inference)
  assert(inference == nil or type(inference) == "table", "inference must be a table")
  return {
    kind = "fixed",
    value = {
      backend = nonempty(backend, "backend"),
      provider = nonempty(provider, "provider"),
      model = nonempty(model, "model"),
      inference = inference or {},
    },
  }
end

function M.routed_target(profile)
  return {
    kind = "routed",
    value = nonempty(profile, "profile"),
  }
end

function M.new(options)
  options = options or {}
  local client = setmetatable({
    next_id = 1,
    pending = {},
    stopped = false,
    on_event = options.on_event or function() end,
  }, Client)

  client.transport = Transport.new({
    command = options.command,
    cwd = options.cwd,
    on_message = function(message)
      client:_dispatch_safely(message)
    end,
    on_stderr = options.on_stderr,
    on_exit = function(result)
      client.stopped = true
      local pending = client.pending
      client.pending = {}
      for id, callback in pairs(pending) do
        finish(callback, nil, {
          code = "transport_closed",
          message = "conductor exited before request " .. id .. " completed",
        })
      end
      if options.on_exit then
        options.on_exit(result)
      end
    end,
  })

  return client
end

function Client:_dispatch(message)
  assert(type(message) == "table" and type(message.type) == "string", "invalid conductor message")

  if message.type == "event" then
    self.on_event(message.event)
    return
  end

  assert(message.type == "response", "unknown conductor message type: " .. message.type)
  local callback = self.pending[message.id]
  if not callback then
    return
  end
  self.pending[message.id] = nil

  if message.status == "ok" then
    callback(message.result, nil)
  elseif message.status == "error" then
    callback(nil, message.error)
  else
    error("invalid conductor response status: " .. tostring(message.status))
  end
end

function Client:_dispatch_safely(message)
  local ok, error_message = xpcall(function()
    self:_dispatch(message)
  end, debug.traceback)
  if not ok then
    vim.schedule(function()
      vim.notify("Phenix conductor message handler failed: " .. tostring(error_message), vim.log.levels.ERROR)
    end)
  end
end

function Client:_request(command, callback)
  assert(not self.stopped, "conductor client is stopped")
  assert(type(command) == "table" and type(command.type) == "string", "conductor command must have a type")

  local id = self.next_id
  self.next_id = self.next_id + 1
  self.pending[id] = callback or function() end

  local ok, error_message = self.transport:write({ id = id, command = command })
  if not ok then
    local pending = self.pending[id]
    self.pending[id] = nil
    finish(pending, nil, {
      code = "transport_error",
      message = tostring(error_message),
    })
  end
  return id
end

function Client:start(after_sequence, callback)
  self.transport:start(function(error_message)
    if error_message then
      finish(callback, nil, { code = "transport_error", message = tostring(error_message) })
      return
    end
    self:initialize(after_sequence, callback)
  end)
end

function Client:initialize(after_sequence, callback)
  assert(after_sequence == nil or type(after_sequence) == "number", "after_sequence must be a number")
  return self:_request({ type = "initialize", after_sequence = after_sequence }, callback)
end

function Client:snapshot(callback)
  return self:_request({ type = "get_snapshot" }, callback)
end

function Client:create_session(options, callback)
  options = options or {}
  assert(type(options.target) == "table", "session target is required")
  return self:_request({
    type = "create_session",
    parent_session = options.parent_session,
    name = options.name,
    target = options.target,
  }, callback)
end

function Client:fork_session(session_id, name, callback)
  return self:_request({
    type = "fork_session",
    session_id = nonempty(session_id, "session_id"),
    name = name,
  }, callback)
end

function Client:rename_session(session_id, name, callback)
  return self:_request({
    type = "rename_session",
    session_id = nonempty(session_id, "session_id"),
    name = nonempty(name, "name"),
  }, callback)
end

function Client:set_session_target(session_id, target, callback)
  assert(type(target) == "table", "target is required")
  return self:_request({
    type = "set_session_target",
    session_id = nonempty(session_id, "session_id"),
    target = target,
  }, callback)
end

function Client:submit(session_id, text, callback)
  return self:_request({
    type = "submit",
    session_id = nonempty(session_id, "session_id"),
    text = nonempty(text, "text"),
  }, callback)
end

function Client:cancel_execution(execution_id, callback)
  return self:_request({
    type = "cancel_execution",
    execution_id = nonempty(execution_id, "execution_id"),
  }, callback)
end

function Client:refresh_backend_catalog(backend_id, callback)
  return self:_request({
    type = "refresh_backend_catalog",
    backend_id = nonempty(backend_id, "backend_id"),
  }, callback)
end

function Client:select_authentication(backend_id, method_id, callback)
  return self:_request({
    type = "select_authentication",
    backend_id = nonempty(backend_id, "backend_id"),
    method_id = nonempty(method_id, "method_id"),
  }, callback)
end

function Client:stop()
  if self.stopped then
    return
  end
  self.stopped = true
  self.transport:stop()
end

M.Client = Client
return M
