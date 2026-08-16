local M = {}

local Transport = {}
Transport.__index = Transport

local MAX_MESSAGES_PER_DRAIN = 256

local function schedule(callback, ...)
  local args = { ... }
  vim.schedule(function()
    callback(unpack(args))
  end)
end

local function normalize_command(command)
  if type(command) == "string" then
    return { command }
  end
  assert(type(command) == "table" and #command > 0, "transport command must be a string or non-empty argv table")
  return vim.deepcopy(command)
end

local function normalize_socket(socket)
  if socket == nil then
    return nil
  end
  assert(type(socket) == "string" and vim.trim(socket) ~= "", "transport socket must be a non-empty path")
  return vim.fs.normalize(socket)
end

function M.new(options)
  options = options or {}
  local socket = normalize_socket(options.socket)
  assert(not (socket and options.command), "transport accepts either command or socket, not both")
  return setmetatable({
    mode = socket and "socket" or "process",
    socket = socket,
    command = socket and nil or normalize_command(options.command or "phenix-conductor"),
    cwd = options.cwd or vim.fn.getcwd(),
    stdout_tail = "",
    stdout_chunks = {},
    stdout_scheduled = false,
    process = nil,
    pipe = nil,
    connected = false,
    stopped = false,
    exit_reported = false,
    on_message = options.on_message or function() end,
    on_stderr = options.on_stderr or function() end,
    on_exit = options.on_exit or function() end,
  }, Transport)
end

function Transport:_report(message)
  pcall(self.on_stderr, tostring(message))
end

function Transport:_report_exit(result)
  if self.exit_reported then
    return
  end
  self.exit_reported = true
  schedule(function()
    pcall(self.on_exit, result)
  end)
end

function Transport:write(message)
  if self.stopped then
    return false, "conductor transport is stopped"
  end

  local payload = vim.json.encode(message) .. "\n"
  if self.mode == "process" then
    if not self.process then
      return false, "conductor process is not running"
    end
    local ok, error_message = pcall(self.process.write, self.process, payload)
    if not ok then
      return false, tostring(error_message)
    end
    return true
  end

  if not self.pipe or not self.connected then
    return false, "conductor socket is not connected"
  end
  local ok, request, error_message = pcall(self.pipe.write, self.pipe, payload)
  if not ok then
    return false, tostring(request)
  end
  if request == nil then
    return false, tostring(error_message or "socket write failed")
  end
  return true
end

function Transport:_dispatch_safely(message)
  local ok, error_message = xpcall(function()
    self.on_message(message)
  end, debug.traceback)
  if not ok then
    self:_report("conductor message handler failed: " .. tostring(error_message))
  end
end

function Transport:_consume_stdout(data, max_messages)
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
      local ok, message = pcall(vim.json.decode, line, { luanil = { object = true } })
      if ok then
        self:_dispatch_safely(message)
      else
        self:_report("invalid conductor JSON: " .. tostring(message) .. "\n" .. line)
      end
    end
  end
  self.stdout_tail = text:sub(start)
  return self.stdout_tail:find("\n", 1, true) ~= nil
end

function Transport:_schedule_stdout_drain()
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

function Transport:_queue_stdout(data)
  if not data or data == "" then
    return
  end
  self.stdout_chunks[#self.stdout_chunks + 1] = data
  self:_schedule_stdout_drain()
end

function Transport:_close_pipe()
  local pipe = self.pipe
  self.pipe = nil
  self.connected = false
  if not pipe then
    return
  end
  pcall(pipe.read_stop, pipe)
  if not pipe:is_closing() then
    pcall(pipe.close, pipe)
  end
end

function Transport:_start_socket(callback)
  local pipe, pipe_error = vim.uv.new_pipe(false)
  if not pipe then
    callback(tostring(pipe_error or "failed to create conductor socket handle"))
    return
  end
  self.pipe = pipe

  local connected = function(error_message)
    if self.stopped then
      self:_close_pipe()
      return
    end
    if error_message then
      self:_close_pipe()
      schedule(callback, tostring(error_message))
      return
    end

    local ok, read_result, read_error = pcall(pipe.read_start, pipe, function(read_error_message, data)
      if read_error_message then
        schedule(function()
          self:_report(read_error_message)
        end)
        self:_close_pipe()
        if not self.stopped then
          self.stopped = true
          self:_report_exit({ code = 1, signal = 0, transport = "socket" })
        end
        return
      end
      if data == nil then
        self:_close_pipe()
        if not self.stopped then
          self.stopped = true
          self:_report_exit({ code = 0, signal = 0, transport = "socket" })
        end
        return
      end
      self:_queue_stdout(data)
    end)
    if not ok or read_result == nil then
      self:_close_pipe()
      schedule(callback, tostring((not ok and read_result) or read_error or "failed to read conductor socket"))
      return
    end

    self.connected = true
    schedule(callback, nil)
  end

  local ok, request, connect_error = pcall(pipe.connect, pipe, self.socket, connected)
  if not ok or request == nil then
    self:_close_pipe()
    schedule(callback, tostring((not ok and request) or connect_error or "failed to connect conductor socket"))
  end
end

function Transport:_start_process(callback)
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
      self:_report_exit(result)
    end)
  end)

  if not ok then
    callback(tostring(process_or_error))
    return
  end
  self.process = process_or_error
  callback(nil)
end

function Transport:start(callback)
  assert(not self.process and not self.pipe, "transport has already been started")
  callback = callback or function() end
  if self.mode == "socket" then
    self:_start_socket(callback)
  else
    self:_start_process(callback)
  end
end

function Transport:stop()
  if self.stopped then
    return
  end
  self.stopped = true

  if self.mode == "socket" then
    -- A frontend owns only its connection. Closing a socket transport must
    -- never signal or terminate the independently persistent conductor.
    self:_close_pipe()
    return
  end

  if self.process then
    pcall(self.process.write, self.process, nil)
    pcall(self.process.kill, self.process, "sigterm")
    self.process = nil
  end
end

M.Transport = Transport

return M
