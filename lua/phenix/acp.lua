-- Temporary ACP compatibility client.
--
-- Process lifecycle and line-delimited JSON framing live in phenix.transport.
-- JSON-RPC request semantics, the ACP handshake and ACP client callbacks remain
-- isolated here until the frontend switches to the Phenix-native conductor
-- protocol.
local Transport = require("phenix.transport")

local M = {}

local Client = {}
Client.__index = Client

local function schedule(callback, ...)
  local args = { ... }
  vim.schedule(function()
    callback(unpack(args))
  end)
end

local function permission_request(handler, params, respond)
  if not handler then
    respond({ outcome = { outcome = "cancelled" } })
    return
  end

  local finished = false
  local function finish(option_id)
    if finished then
      return
    end
    finished = true
    if option_id then
      respond({
        outcome = {
          outcome = "selected",
          optionId = option_id,
        },
      })
    else
      respond({ outcome = { outcome = "cancelled" } })
    end
  end

  local ok, error_message = xpcall(function()
    handler(params, finish)
  end, debug.traceback)
  if not ok then
    finish(nil)
    vim.schedule(function()
      vim.notify("Phenix permission handler failed: " .. tostring(error_message), vim.log.levels.ERROR)
    end)
  end
end

function M.new(options)
  options = options or {}
  local client = setmetatable({
    next_id = 1,
    pending = {},
    stopped = false,
    on_notification = options.on_notification or function() end,
    on_permission = options.on_permission,
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
      for id, pending in pairs(client.pending) do
        client.pending[id] = nil
        pcall(pending, nil, {
          code = -32001,
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

function Client:_write(message)
  return self.transport:write(message)
end

function Client:request(method, params, callback)
  assert(type(method) == "string" and method ~= "", "request method must be non-empty")
  local id = self.next_id
  self.next_id = self.next_id + 1
  self.pending[id] = callback or function() end
  local ok, error_message = self:_write({
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  })
  if not ok then
    local pending = self.pending[id]
    self.pending[id] = nil
    schedule(function()
      pending(nil, { code = -32000, message = error_message })
    end)
  end
  return id
end

function Client:notify(method, params)
  assert(type(method) == "string" and method ~= "", "notification method must be non-empty")
  return self:_write({
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  })
end

function Client:respond(id, result, error_value)
  local message = { jsonrpc = "2.0", id = id }
  if error_value then
    message.error = error_value
  else
    message.result = result or {}
  end
  return self:_write(message)
end

function Client:_dispatch(message)
  if message.id ~= nil and message.method == nil then
    local callback = self.pending[message.id]
    if not callback then
      return
    end
    self.pending[message.id] = nil
    callback(message.result, message.error)
    return
  end

  if message.method and message.id ~= nil then
    local responded = false
    local function respond(result, error_value)
      if responded then
        return
      end
      responded = true
      self:respond(message.id, result, error_value)
    end
    if message.method == "session/request_permission" then
      permission_request(self.on_permission, message.params or {}, respond)
      return
    end
    respond(nil, { code = -32601, message = "unsupported legacy ACP client method: " .. message.method })
    return
  end

  if message.method then
    self.on_notification(message.method, message.params or {})
  end
end

function Client:_dispatch_safely(message)
  local ok, error_message = xpcall(function()
    self:_dispatch(message)
  end, debug.traceback)
  if not ok then
    vim.schedule(function()
      vim.notify("Phenix ACP message handler failed: " .. tostring(error_message), vim.log.levels.ERROR)
    end)
  end
end

function Client:start(callback)
  callback = callback or function() end
  self.transport:start(function(start_error)
    if start_error then
      callback(nil, { code = -32000, message = start_error })
      return
    end
    self:request("initialize", {
      protocolVersion = 1,
      clientCapabilities = {},
      clientInfo = {
        name = "phenix-nvim",
        version = "0",
      },
    }, callback)
  end)
end

function Client:stop()
  self.stopped = true
  self.transport:stop()
end

M.Client = Client

return M
