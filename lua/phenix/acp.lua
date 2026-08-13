local M = {}

local Client = {}
Client.__index = Client

local MAX_MESSAGES_PER_DRAIN = 256

local function schedule(callback, ...)
  local args = { ... }
  vim.schedule(function()
    callback(unpack(args))
  end)
end

local function rpc_error(code, message)
  return { code = code, message = message }
end

local function normalize_command(command)
  if type(command) == "string" then
    return { command }
  end
  assert(type(command) == "table" and #command > 0, "ACP command must be a string or non-empty argv table")
  return vim.deepcopy(command)
end

function M.new(options)
  options = options or {}
  return setmetatable({
    command = normalize_command(options.command or "phenix-conductor"),
    cwd = options.cwd or vim.fn.getcwd(),
    next_id = 1,
    pending = {},
    stdout_tail = "",
    stdout_chunks = {},
    stdout_scheduled = false,
    process = nil,
    stopped = false,
    on_notification = options.on_notification or function() end,
    on_permission = options.on_permission,
    on_stderr = options.on_stderr or function() end,
    on_exit = options.on_exit or function() end,
  }, Client)
end

function Client:_report(message)
  local ok = pcall(self.on_stderr, tostring(message))
  if not ok then
    -- Error reporting must never be able to break ACP frame consumption.
  end
end

function Client:_write(message)
  if not self.process or self.stopped then
    return false, "ACP process is not running"
  end
  local ok, error_message = pcall(self.process.write, self.process, vim.json.encode(message) .. "\n")
  if not ok then
    return false, tostring(error_message)
  end
  return true
end

function Client:request(method, params, callback)
  assert(type(method) == "string" and method ~= "", "ACP request method must be non-empty")
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
      local callback_ok, callback_error = xpcall(function()
        pending(nil, rpc_error(-32000, error_message))
      end, debug.traceback)
      if not callback_ok then
        self:_report("ACP request callback failed: " .. tostring(callback_error))
      end
    end)
  end
  return id
end

function Client:notify(method, params)
  assert(type(method) == "string" and method ~= "", "ACP notification method must be non-empty")
  return self:_write({
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  })
end

function Client:_respond(id, result, error_value)
  local message = {
    jsonrpc = "2.0",
    id = id,
  }
  if error_value then
    message.error = error_value
  else
    message.result = result or {}
  end
  self:_write(message)
end

function Client:_permission_request(message)
  local params = message.params or {}
  if not self.on_permission then
    self:_respond(message.id, {
      outcome = { outcome = "cancelled" },
    })
    return
  end

  local responded = false
  local function respond(option_id)
    if responded then
      return
    end
    responded = true
    if option_id then
      self:_respond(message.id, {
        outcome = {
          outcome = "selected",
          optionId = option_id,
        },
      })
    else
      self:_respond(message.id, {
        outcome = { outcome = "cancelled" },
      })
    end
  end

  local ok, error_message = xpcall(function()
    self.on_permission(params, respond)
  end, debug.traceback)
  if not ok then
    self:_report("ACP permission handler failed: " .. tostring(error_message))
    respond(nil)
  end
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
    if message.method == "session/request_permission" then
      self:_permission_request(message)
    else
      self:_respond(message.id, nil, rpc_error(-32601, "unsupported ACP client method: " .. message.method))
    end
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
    self:_report("ACP message handler failed: " .. tostring(error_message))
  end
end

function Client:_consume_stdout(data, max_messages)
  local text = self.stdout_tail .. (data or "")
  local start = 1
  local processed = 0
  local limit = max_messages or math.huge
  while processed < limit do
    local newline = text:find("\n", start, true)
    if not newline then
      break
    end
    local line = text:sub(start, newline - 1):gsub("\r$", "")
    start = newline + 1
    processed = processed + 1
    if line ~= "" then
      local ok, message = pcall(vim.json.decode, line)
      if ok then
        self:_dispatch_safely(message)
      else
        self:_report("invalid ACP JSON: " .. tostring(message) .. "\n" .. line)
      end
    end
  end
  self.stdout_tail = text:sub(start)
  return self.stdout_tail:find("\n", 1, true) ~= nil
end

function Client:_schedule_stdout_drain()
  if self.stdout_scheduled then
    return
  end
  self.stdout_scheduled = true
  vim.schedule(function()
    self.stdout_scheduled = false
    local chunks = self.stdout_chunks
    self.stdout_chunks = {}
    local more_frames = self:_consume_stdout(table.concat(chunks), MAX_MESSAGES_PER_DRAIN)
    if more_frames or #self.stdout_chunks > 0 then
      self:_schedule_stdout_drain()
    end
  end)
end

function Client:_queue_stdout(data)
  if not data or data == "" then
    return
  end
  self.stdout_chunks[#self.stdout_chunks + 1] = data
  self:_schedule_stdout_drain()
end

function Client:start(callback)
  assert(not self.process, "ACP client has already been started")
  callback = callback or function() end

  local ok, process_or_error = pcall(vim.system, self.command, {
    cwd = self.cwd,
    stdin = true,
    text = true,
    stdout = function(error_message, data)
      if error_message then
        schedule(function()
          self:_report(error_message)
        end)
        return
      end
      self:_queue_stdout(data)
    end,
    stderr = function(error_message, data)
      schedule(function()
        if error_message then
          self:_report(error_message)
        elseif data and data ~= "" then
          self:_report(data)
        end
      end)
    end,
  }, function(result)
    schedule(function()
      self.stopped = true
      self.process = nil
      for id, pending in pairs(self.pending) do
        self.pending[id] = nil
        local callback_ok, callback_error = xpcall(function()
          pending(nil, rpc_error(-32001, "ACP process exited before request " .. id .. " completed"))
        end, debug.traceback)
        if not callback_ok then
          self:_report("ACP request callback failed during process exit: " .. tostring(callback_error))
        end
      end
      local exit_ok, exit_error = xpcall(function()
        self.on_exit(result)
      end, debug.traceback)
      if not exit_ok then
        self:_report("ACP exit handler failed: " .. tostring(exit_error))
      end
    end)
  end)

  if not ok then
    callback(nil, rpc_error(-32000, tostring(process_or_error)))
    return
  end
  self.process = process_or_error

  self:request("initialize", {
    protocolVersion = 1,
    clientCapabilities = {},
    clientInfo = {
      name = "phenix-nvim",
      version = "0",
    },
  }, callback)
end

function Client:stop()
  if self.stopped then
    return
  end
  self.stopped = true
  if self.process then
    pcall(self.process.write, self.process, nil)
    pcall(self.process.kill, self.process, "sigterm")
    self.process = nil
  end
end

M.Client = Client

return M
