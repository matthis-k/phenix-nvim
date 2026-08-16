local function fail(message)
  error("N7 socket transport: " .. message, 0)
end

local function assert_true(value, message)
  if not value then
    fail(message)
  end
end

local function wait_for(predicate, message, timeout)
  if not vim.wait(timeout or 5000, predicate, 10) then
    fail(message)
  end
end

local socket_path = vim.fn.tempname() .. ".sock"
local server = assert(vim.uv.new_pipe(false))
local accepted = {}
local connection_count = 0
local sessions = {}

local model = {
  backend = "fixture",
  provider = "fixture",
  model = "fixture-model",
  inference = {},
}
local catalog = {
  backend = "fixture",
  models = {
    { target = model, name = "Fixture Model" },
  },
  authentication_state = "not_required",
  authentication_methods = {},
}

local function snapshot()
  local values = {}
  for _, session in pairs(sessions) do
    values[#values + 1] = vim.deepcopy(session)
  end
  table.sort(values, function(left, right)
    return left.id < right.id
  end)
  return {
    sessions = values,
    executions = {},
    last_event_sequence = 0,
  }
end

local function write_response(client, id, result)
  client:write(vim.json.encode({
    type = "response",
    id = id,
    status = "ok",
    result = result,
  }) .. "\n")
end

local function handle_request(client, request)
  local command = request.command or {}
  if command.type == "initialize" then
    write_response(client, request.id, {
      type = "initialized",
      snapshot = snapshot(),
      events = {},
      backends = { catalog },
    })
    return
  end
  if command.type == "create_session" then
    local session = {
      id = "session-1",
      parent_session = command.parent_session,
      name = command.name,
      config_revision = "fixture-revision",
      default_target = vim.deepcopy(command.target),
    }
    sessions[session.id] = session
    write_response(client, request.id, { type = "session", session = session })
    return
  end
  if command.type == "get_snapshot" then
    write_response(client, request.id, {
      type = "snapshot",
      snapshot = snapshot(),
      backends = { catalog },
    })
    return
  end
  client:write(vim.json.encode({
    type = "response",
    id = request.id,
    status = "error",
    error = {
      code = "invalid_request",
      message = "unsupported fixture command: " .. tostring(command.type),
      session_id = vim.NIL,
      execution_id = vim.NIL,
    },
  }) .. "\n")
end

assert_true(server:bind(socket_path) ~= nil, "failed to bind local Unix socket")
assert_true(server:listen(16, function(error_message)
  assert(not error_message, error_message)
  local client = assert(vim.uv.new_pipe(false))
  assert(server:accept(client))
  connection_count = connection_count + 1
  accepted[#accepted + 1] = client

  local tail = ""
  client:read_start(function(read_error, data)
    assert(not read_error, read_error)
    if data == nil then
      if not client:is_closing() then
        client:close()
      end
      return
    end
    local text = tail .. data
    local start = 1
    while true do
      local newline = text:find("\n", start, true)
      if not newline then
        break
      end
      local line = text:sub(start, newline - 1)
      start = newline + 1
      if line ~= "" then
        handle_request(client, vim.json.decode(line))
      end
    end
    tail = text:sub(start)
  end)
end) ~= nil, "failed to listen on local Unix socket")

local phenix = require("phenix")
phenix.setup({ conductor_socket = socket_path })
assert_true(Phenix.config.agent.conductor_socket == socket_path, "socket deployment setting was not retained")

local session = phenix.toggle({ fullscreen = true })
wait_for(function()
  return session:is_ready()
end, "frontend did not initialize over conductor socket")
assert_true(connection_count == 1, "frontend did not use exactly one socket connection")
assert_true(session.controller.client.transport.mode == "socket", "frontend did not select socket transport")
assert_true(session.controller.client.transport.process == nil, "socket frontend unexpectedly spawned a conductor process")
assert_true(session.controller:state().connection == "connected", "socket-backed controller is not connected")
assert_true(session.controller:session().id == "session-1", "socket-backed session was not projected")

phenix.shutdown()
wait_for(function()
  return accepted[1]:is_closing()
end, "frontend shutdown did not close its socket connection")
assert_true(not server:is_closing(), "frontend shutdown closed the conductor service listener")

local probe = assert(vim.uv.new_pipe(false))
local probe_connected = false
local probe_error = nil
probe:connect(socket_path, function(error_message)
  probe_error = error_message
  probe_connected = error_message == nil
end)
wait_for(function()
  return probe_connected or probe_error ~= nil
end, "service socket did not accept a new frontend after shutdown")
assert_true(probe_error == nil, "service socket was not reusable after frontend shutdown: " .. tostring(probe_error))
wait_for(function()
  return connection_count == 2
end, "service listener did not observe the replacement frontend")

if not probe:is_closing() then
  probe:close()
end
for _, client in ipairs(accepted) do
  if not client:is_closing() then
    client:close()
  end
end
if not server:is_closing() then
  server:close()
end
pcall(vim.uv.fs_unlink, socket_path)

print("N7 persistent conductor socket transport passed")
