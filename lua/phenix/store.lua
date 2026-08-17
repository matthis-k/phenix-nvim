local M = {}
local Store = {}
Store.__index = Store

local function index_by_id(values, name)
  assert(type(values) == "table", name .. " must be a table")
  local indexed = {}
  for _, value in ipairs(values) do
    assert(type(value) == "table" and type(value.id) == "string", name .. " entry must have an id")
    indexed[value.id] = vim.deepcopy(value)
  end
  return indexed
end

local function sequence_error(code, message, extra)
  local err = { code = code, message = message }
  for key, value in pairs(extra or {}) do
    err[key] = value
  end
  return err
end

function M.new()
  return setmetatable({
    sessions = {},
    executions = {},
    last_event_sequence = 0,
    connection = "disconnected",
    needs_resync = false,
  }, Store)
end

function Store:set_connection(state)
  assert(state == "connected" or state == "disconnected" or state == "error", "invalid connection state")
  self.connection = state
end

function Store:put_session(session)
  assert(type(session) == "table" and type(session.id) == "string", "session must have an id")
  self.sessions[session.id] = vim.deepcopy(session)
end

function Store:replace_snapshot(snapshot)
  assert(type(snapshot) == "table", "snapshot must be a table")
  assert(type(snapshot.last_event_sequence) == "number", "snapshot event sequence must be a number")

  self.sessions = index_by_id(snapshot.sessions or {}, "sessions")
  self.executions = index_by_id(snapshot.executions or {}, "executions")
  self.last_event_sequence = snapshot.last_event_sequence
  self.needs_resync = false
end

function Store:apply_event(event)
  assert(type(event) == "table", "event must be a table")
  assert(type(event.sequence) == "number", "event sequence must be a number")

  if event.sequence <= self.last_event_sequence then
    return "duplicate"
  end

  local expected = self.last_event_sequence + 1
  if self.needs_resync or event.sequence ~= expected then
    self.needs_resync = true
    return nil, sequence_error("sequence_gap", "conductor event sequence is not contiguous", {
      expected = expected,
      actual = event.sequence,
    })
  end

  local kind = event.kind
  assert(type(kind) == "table" and type(kind.type) == "string", "event kind must be typed")

  if kind.type == "execution_state_changed" then
    local execution = self.executions[event.execution_id]
    if execution then
      execution.state = kind.state
    end
  end

  self.last_event_sequence = event.sequence
  return "applied"
end

function Store:initialize(snapshot, events)
  self:replace_snapshot(snapshot)
  for _, event in ipairs(events or {}) do
    local status, err = self:apply_event(event)
    if not status then
      return nil, err
    end
  end
  return true
end

M.Store = Store
return M