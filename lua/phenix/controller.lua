local Conductor = require("phenix.conductor")
local Projection = require("phenix.projection")
local Store = require("phenix.store")

local M = {}
local Controller = {}
Controller.__index = Controller

local terminal_states = {
  completed = true,
  failed = true,
  cancelled = true,
  interrupted = true,
}

local function noop() end

local function execution_number(id)
  return tonumber(tostring(id or ""):match("(%d+)$")) or -1
end

local function target_from_catalogs(catalogs)
  for _, catalog in ipairs(catalogs or {}) do
    for _, model in ipairs(catalog.models or {}) do
      if type(model.target) == "table" then
        return { kind = "fixed", value = vim.deepcopy(model.target) }
      end
    end
  end
  return nil
end

local function normalize_error(code, message)
  return { code = code, message = tostring(message) }
end

local function validate_event_range(events, first_sequence, last_sequence)
  if type(events) ~= "table" then
    return nil, normalize_error("invalid_event_history", "conductor event history must be a table")
  end
  local expected = first_sequence
  for _, event in ipairs(events) do
    if type(event) ~= "table" or type(event.sequence) ~= "number" then
      return nil, normalize_error("invalid_event_history", "conductor event history contains an invalid event")
    end
    if event.sequence ~= expected then
      return nil, normalize_error(
        "invalid_event_history",
        string.format("conductor event history is not contiguous: expected %d, got %d", expected, event.sequence)
      )
    end
    expected = expected + 1
  end
  if expected ~= last_sequence + 1 then
    return nil, normalize_error(
      "invalid_event_history",
      string.format("conductor event history ends at %d, but snapshot ends at %d", expected - 1, last_sequence)
    )
  end
  return true
end

local function sorted_sessions(store)
  local sessions = {}
  for _, session in pairs(store.sessions or {}) do
    sessions[#sessions + 1] = vim.deepcopy(session)
  end
  table.sort(sessions, function(left, right)
    return tostring(left.id) < tostring(right.id)
  end)
  return sessions
end

function M.new(options)
  options = options or {}
  local initial_projection = Projection.new()
  local controller = setmetatable({
    options = vim.deepcopy(options),
    store = Store.new(),
    projection = initial_projection,
    projections = {},
    catalogs = {},
    session_id = options.session_id,
    preferred_target = vim.deepcopy(options.target),
    configured_target = vim.deepcopy(options.configured_target),
    reuse_existing_sessions = options.reuse_existing_sessions == true,
    select_existing_session = options.select_existing_session,
    stopped = false,
    resyncing = false,
    refreshing = false,
    mutation_pending = false,
    submission_pending = false,
    queued_events = {},
    refresh_queue = {},
    on_ready = options.on_ready or noop,
    on_event = options.on_event or noop,
    on_resync = options.on_resync or noop,
    on_state = options.on_state or noop,
    on_error = options.on_error or noop,
    on_exit = options.on_exit or noop,
  }, Controller)
  if controller.session_id then
    controller.projections[controller.session_id] = initial_projection
  end

  local client_options = {
    command = options.command,
    cwd = options.cwd,
    on_event = function(event)
      controller:_event_safely(event)
    end,
    on_stderr = function(message)
      controller.on_error(normalize_error("conductor_stderr", vim.trim(message)))
    end,
    on_exit = function(result)
      controller.store:set_connection(result.code == 0 and "disconnected" or "error")
      controller.on_state(controller:state())
      controller.on_exit(result)
    end,
  }
  controller.client = options.client_factory and options.client_factory(client_options) or Conductor.new(client_options)
  if options.reuse_existing_sessions == nil then
    controller.reuse_existing_sessions = controller.client.persistent == true
  end
  if controller.reuse_existing_sessions and controller.select_existing_session == nil then
    controller.select_existing_session = require("phenix.session_selector").select
  end
  return controller
end

function Controller:_projection_for(session_id)
  assert(type(session_id) == "string" and session_id ~= "", "projection session id is required")
  local projection = self.projections[session_id]
  if not projection then
    projection = Projection.new()
    self.projections[session_id] = projection
  end
  return projection
end

function Controller:_select_projection(session_id)
  self.projection = self:_projection_for(session_id)
end

function Controller:_fail(error_value)
  self.store:set_connection("error")
  self.on_state(self:state())
  self.on_error(error_value or normalize_error("frontend_error", "unknown frontend error"))
end

function Controller:_install_initialized(result)
  if type(result) ~= "table" or result.type ~= "initialized" or type(result.snapshot) ~= "table" then
    return nil, normalize_error("invalid_initialize", "conductor returned an invalid initialize reply")
  end
  local last_sequence = result.snapshot.last_event_sequence
  if type(last_sequence) ~= "number" then
    return nil, normalize_error("invalid_initialize", "conductor snapshot has no event sequence")
  end
  local events = result.events or {}
  local valid, history_error = validate_event_range(events, 1, last_sequence)
  if not valid then
    return nil, history_error
  end
  local ok, err = self.store:initialize(result.snapshot, events)
  if not ok then
    return nil, err
  end
  self.projections = {}
  self.projection = Projection.new()
  for _, event in ipairs(events) do
    self:_projection_for(event.session_id):apply_event(event)
  end
  if self.session_id then
    self:_select_projection(self.session_id)
  end
  self.catalogs = vim.deepcopy(result.backends or {})
  self.store:set_connection("connected")
  return true
end

function Controller:_use_initialized_session(session, callback)
  if type(session) ~= "table" or type(session.id) ~= "string" or not self.store.sessions[session.id] then
    callback(nil, normalize_error("unknown_session", "selected session does not exist in conductor snapshot"))
    return
  end
  self.session_id = session.id
  self:_select_projection(session.id)
  callback(vim.deepcopy(self.store.sessions[session.id]), nil)
end

function Controller:_create_session(callback)
  local target = self.preferred_target or self.configured_target or target_from_catalogs(self.catalogs)
  if not target then
    callback(nil, normalize_error(
      "no_execution_target",
      "the conductor exposes no model target; configure a typed target or register a backend with a model catalog"
    ))
    return
  end

  self.client:create_session({ target = target }, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    local session = result and result.session
    if type(session) ~= "table" or type(session.id) ~= "string" then
      callback(nil, normalize_error("invalid_session", "conductor returned an invalid session reply"))
      return
    end

    -- SessionCreated is an authoritative mutation reply. Establish the local
    -- session immediately so frontend readiness does not depend on a second
    -- Initialize round trip. The snapshot refresh below is reconciliation,
    -- not part of the session-creation transaction.
    self.store:put_session(session)
    self.session_id = session.id
    self:_select_projection(session.id)
    callback(vim.deepcopy(session), nil)

    self:_refresh_snapshot(function(refresh_error)
      if refresh_error and not self.stopped then
        self.on_error(refresh_error)
        self:_resync()
      end
    end)
  end)
end

function Controller:_choose_session(callback)
  if self.session_id then
    local session = self.store.sessions[self.session_id]
    if not session then
      callback(nil, normalize_error("unknown_session", "configured session does not exist: " .. self.session_id))
      return
    end
    self:_use_initialized_session(session, callback)
    return
  end

  -- Only a target supplied for this frontend open requests a new session.
  -- A setup-configured target remains the creation default when no persisted
  -- session is selected, but must not suppress persistent session resume.
  if self.reuse_existing_sessions and self.preferred_target == nil then
    local sessions = sorted_sessions(self.store)
    if #sessions == 1 then
      self:_use_initialized_session(sessions[1], callback)
      return
    end
    if #sessions > 1 then
      if type(self.select_existing_session) ~= "function" then
        callback(nil, normalize_error(
          "session_selection_required",
          "multiple persisted sessions exist and no frontend session selector is configured"
        ))
        return
      end
      self.select_existing_session(vim.deepcopy(sessions), function(choice, selection_error)
        if selection_error then
          callback(nil, selection_error)
          return
        end
        if type(choice) ~= "table" or type(choice.kind) ~= "string" then
          callback(nil, normalize_error("invalid_session_selection", "frontend returned an invalid session selection"))
          return
        end
        if choice.kind == "new" then
          self:_create_session(callback)
          return
        end
        if choice.kind == "existing" and type(choice.session_id) == "string" then
          local selected = self.store.sessions[choice.session_id]
          if not selected then
            callback(nil, normalize_error("unknown_session", "selected session does not exist: " .. choice.session_id))
            return
          end
          self:_use_initialized_session(selected, callback)
          return
        end
        callback(nil, normalize_error("invalid_session_selection", "frontend returned an unsupported session selection"))
      end)
      return
    end
  end

  self:_create_session(callback)
end

function Controller:start(callback)
  callback = callback or noop
  self.store:set_connection("disconnected")
  self.client:start(nil, function(result, err)
    if err then
      self:_fail(err)
      callback(nil, err)
      return
    end
    local ok, install_error = self:_install_initialized(result)
    if not ok then
      self:_fail(install_error)
      callback(nil, install_error)
      return
    end
    self:_choose_session(function(session, session_error)
      if session_error then
        self:_fail(session_error)
        callback(nil, session_error)
        return
      end
      self.on_resync(self:projection_blocks())
      self.on_state(self:state())
      self.on_ready(vim.deepcopy(session))
      callback(vim.deepcopy(session), nil)
    end)
  end)
end

function Controller:_replay_buffered_events(events, covered_sequence)
  table.sort(events, function(left, right)
    return left.sequence < right.sequence
  end)
  for _, event in ipairs(events) do
    if event.sequence > covered_sequence then
      self:_event_safely(event)
    end
  end
end

function Controller:_drain_refresh_queue()
  if self.refreshing or self.resyncing or self.stopped then
    return
  end
  local callback = table.remove(self.refresh_queue, 1)
  if callback then
    self:_refresh_snapshot(callback)
  end
end

function Controller:_fail_refresh_queue(error_value)
  local callbacks = self.refresh_queue
  self.refresh_queue = {}
  for _, callback in ipairs(callbacks) do
    callback(error_value)
  end
end

function Controller:_refresh_snapshot(callback)
  callback = callback or noop
  if self.refreshing or self.resyncing then
    self.refresh_queue[#self.refresh_queue + 1] = callback
    return
  end

  local baseline = self.store.last_event_sequence
  self.refreshing = true
  self.queued_events = {}
  self.client:initialize(baseline, function(result, err)
    local queued = self.queued_events
    self.queued_events = {}
    self.refreshing = false

    if err then
      self:_replay_buffered_events(queued, self.store.last_event_sequence)
      callback(err)
      self:_drain_refresh_queue()
      return
    end
    if type(result) ~= "table" or result.type ~= "initialized" or type(result.snapshot) ~= "table" then
      local sync_error = normalize_error("invalid_snapshot", "conductor returned an invalid synchronization reply")
      self:_replay_buffered_events(queued, self.store.last_event_sequence)
      self:_resync()
      callback(sync_error)
      return
    end

    local snapshot_sequence = result.snapshot.last_event_sequence
    if type(snapshot_sequence) ~= "number" or snapshot_sequence < baseline then
      local sync_error = normalize_error("invalid_snapshot", "conductor returned a stale synchronization snapshot")
      self:_replay_buffered_events(queued, self.store.last_event_sequence)
      self:_resync()
      callback(sync_error)
      return
    end
    local history = result.events or {}
    local valid, history_error = validate_event_range(history, baseline + 1, snapshot_sequence)
    if not valid then
      self:_replay_buffered_events(queued, self.store.last_event_sequence)
      self:_resync()
      callback(history_error)
      return
    end

    self.store:replace_snapshot(result.snapshot)
    self.catalogs = vim.deepcopy(result.backends or self.catalogs)
    for _, event in ipairs(history) do
      self:_projection_for(event.session_id):apply_event(event)
      self.on_event(vim.deepcopy(event))
    end
    if self.session_id then
      self:_select_projection(self.session_id)
    end
    self:_replay_buffered_events(queued, snapshot_sequence)
    self.on_state(self:state())
    callback(nil)
    self:_drain_refresh_queue()
  end)
end

function Controller:_resync()
  if self.resyncing or self.refreshing or self.stopped then
    return
  end
  self.resyncing = true
  self.queued_events = {}
  self.client:initialize(nil, function(result, err)
    local queued = self.queued_events
    self.queued_events = {}
    if err then
      self.resyncing = false
      self:_fail(err)
      self:_fail_refresh_queue(err)
      return
    end
    local ok, install_error = self:_install_initialized(result)
    if not ok then
      self.resyncing = false
      self:_fail(install_error)
      self:_fail_refresh_queue(install_error)
      return
    end
    local covered_sequence = self.store.last_event_sequence
    self.resyncing = false
    self:_replay_buffered_events(queued, covered_sequence)
    self.on_resync(self:projection_blocks())
    self.on_state(self:state())
    self:_drain_refresh_queue()
  end)
end

function Controller:_event(event)
  if self.resyncing or self.refreshing then
    self.queued_events[#self.queued_events + 1] = vim.deepcopy(event)
    return
  end
  local status, err = self.store:apply_event(event)
  if not status then
    self.on_error(err)
    self:_resync()
    return
  end
  if status == "duplicate" then
    return
  end
  self:_projection_for(event.session_id):apply_event(event)
  self.on_event(vim.deepcopy(event))
  self.on_state(self:state())
end

function Controller:_event_safely(event)
  local ok, error_message = xpcall(function()
    self:_event(event)
  end, debug.traceback)
  if not ok then
    self:_fail(normalize_error("event_projection_failed", error_message))
    self:_resync()
  end
end

function Controller:session()
  return self.session_id and vim.deepcopy(self.store.sessions[self.session_id]) or nil
end

function Controller:use_session(session_id)
  local session = self.store.sessions[session_id]
  if not session then
    return nil, normalize_error("unknown_session", "session does not exist: " .. tostring(session_id))
  end
  self.session_id = session_id
  self:_select_projection(session_id)
  self.on_state(self:state())
  return vim.deepcopy(session), nil
end

function Controller:projection_blocks()
  return vim.deepcopy(self.projection.blocks)
end

function Controller:state()
  return {
    connection = self.store.connection,
    session = self:session(),
    activity = self:activity_state(),
    last_event_sequence = self.store.last_event_sequence,
    catalogs = vim.deepcopy(self.catalogs),
    callables = vim.deepcopy(self.callables or {}),
    sessions = vim.deepcopy(self.store.sessions),
    executions = vim.deepcopy(self.store.executions),
  }
end

function Controller:_active_root()
  if self.submission_pending then
    return nil
  end
  local active = nil
  for _, execution in pairs(self.store.executions) do
    if execution.session_id == self.session_id and execution.parent_execution == nil and not terminal_states[execution.state] then
      if not active or execution_number(execution.id) > execution_number(active.id) then
        active = execution
      end
    end
  end
  return active
end

function Controller:activity_state()
  if self.submission_pending then
    return "running"
  end
  return self:_active_root() and "running" or "settled"
end

function Controller:stop()
  if self.stopped then
    return
  end
  self.stopped = true
  self.refresh_queue = {}
  self.client:stop()
  self.store:set_connection("disconnected")
  self.on_state(self:state())
end

require("phenix.controller_actions").attach(Controller, {
  normalize_error = normalize_error,
})

M.Controller = Controller
return M