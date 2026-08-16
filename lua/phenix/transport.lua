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

function M.new(options)
  options = options or {}
  return setmetatable({
    command = normalize_command(options.command or "phenix-conductor"),
    cwd = options.cwd or vim.fn.getcwd(),
    stdout_tail = "",
    stdout_chunks = {},
    stdout_scheduled = false,
    process = nil,
    stopped = false,
    on_message = options.on_message or function() end,
    on_stderr = options.on_stderr or function() end,
    on_exit = options.on_exit or function() end,
  }, Transport)
end

function Transport:_report(message)
  pcall(self.on_stderr, tostring(message))
end

function Transport:write(message)
  if not self.process or self.stopped then
    return false, "conductor process is not running"
  end
  local ok, error_message = pcall(self.process.write, self.process, vim.json.encode(message) .. "\n")
  if not ok then
    return false, tostring(error_message)
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

function Transport:start(callback)
  assert(not self.process, "transport has already been started")
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
      pcall(self.on_exit, result)
    end)
  end)

  if not ok then
    callback(tostring(process_or_error))
    return
  end
  self.process = process_or_error
  callback(nil)
end

function Transport:stop()
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

M.Transport = Transport

return M
