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

function M.new(options)
  options = options or {}
  local controller = setmetatable({
    options = vim.deepcopy(options),
    store = Store.new(),
    projection = Projection.new(),
    catalogs = {},
    session_id = options.session_id,
    preferred_target = vim.deepcopy(options.target),
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
  return controller
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
  self.projection = Projection.new()
  self.projection:apply_events(events)
  self.catalogs = vim.deepcopy(result.backends or {})
  self.store:set_connection("connected")
  return true
end

function Controller:_choose_session(callback)
  if self.session_id then
    local session = self.store.sessions[self.session_id]
    if not session then
      callback(nil, normalize_error("unknown_session", "configured session does not exist: " .. self.session_id))
      return
    end
    callback(vim.deepcopy(session), nil)
    return
  end

  local target = self.preferred_target or target_from_catalogs(self.catalogs)
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
    self.session_id = session.id
    self:_refresh_snapshot(function(refresh_error)
      callback(refresh_error and nil or vim.deepcopy(self.store.sessions[self.session_id] or session), refresh_error)
    end)
  end)
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
      self.projection:apply_event(event)
      self.on_event(vim.deepcopy(event))
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
  self.projection:apply_event(event)
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
  self.on_state(self:state())
  return vim.deepcopy(session), nil
end

function Controller:execution()
  local selected = nil
  for _, execution in pairs(self.store.executions) do
    if execution.session_id == self.session_id
      and execution.parent_execution == nil
      and not terminal_states[execution.state]
    then
      if not selected or execution_number(execution.id) > execution_number(selected.id) then
        selected = execution
      end
    end
  end
  return selected and vim.deepcopy(selected) or nil
end

function Controller:activity_state()
  return (self.submission_pending or self:execution()) and "running" or "settled"
end

function Controller:state()
  return {
    connection = self.store.connection,
    needs_resync = self.store.needs_resync,
    session = self:session(),
    execution = self:execution(),
    activity = self:activity_state(),
    catalogs = vim.deepcopy(self.catalogs),
    last_event_sequence = self.store.last_event_sequence,
  }
end

function Controller:projection_blocks()
  local blocks = {}
  for _, block in ipairs(self.projection.blocks) do
    local execution = self.store.executions[block.execution_id]
    if execution and execution.session_id == self.session_id then
      blocks[#blocks + 1] = vim.deepcopy(block)
    end
  end
  return blocks
end

function Controller:_begin_mutation(callback)
  if self.mutation_pending or self.refreshing or self.resyncing then
    callback(nil, normalize_error("frontend_busy", "frontend state synchronization is already in progress"))
    return false
  end
  self.mutation_pending = true
  return true
end

function Controller:submit(text, callback)
  callback = callback or noop
  if self:execution() then
    callback(nil, normalize_error("execution_active", "the session already has an active execution"))
    return false
  end
  if not self:_begin_mutation(callback) then
    return false
  end
  self.submission_pending = true
  self.on_state(self:state())
  self.client:submit(self.session_id, text, function(result, err)
    if err then
      self.mutation_pending = false
      self.submission_pending = false
      self.on_state(self:state())
      callback(nil, err)
      return
    end
    local execution = result and result.execution
    if type(execution) ~= "table" or type(execution.id) ~= "string" then
      self.mutation_pending = false
      self.submission_pending = false
      self.on_state(self:state())
      callback(nil, normalize_error("invalid_execution", "conductor returned an invalid execution reply"))
      return
    end
    self:_refresh_snapshot(function(refresh_error)
      self.mutation_pending = false
      self.submission_pending = false
      self.on_state(self:state())
      callback(refresh_error and nil or vim.deepcopy(execution), refresh_error)
    end)
  end)
  return true
end

function Controller:cancel(callback)
  callback = callback or noop
  local execution = self:execution()
  if not execution then
    callback(nil, normalize_error("no_active_execution", "there is no active execution to cancel"))
    return false
  end
  if not self:_begin_mutation(callback) then
    return false
  end
  self.client:cancel_execution(execution.id, function(result, err)
    if err then
      self.mutation_pending = false
      callback(nil, err)
      return
    end
    self:_refresh_snapshot(function(refresh_error)
      self.mutation_pending = false
      callback(refresh_error and nil or result, refresh_error)
    end)
  end)
  return true
end

function Controller:set_target(target, callback)
  callback = callback or noop
  if type(target) ~= "table" or (target.kind ~= "fixed" and target.kind ~= "routed") then
    callback(nil, normalize_error("invalid_target", "target must be a typed fixed or routed target"))
    return false
  end
  if not self:_begin_mutation(callback) then
    return false
  end
  self.client:set_session_target(self.session_id, target, function(result, err)
    if err then
      self.mutation_pending = false
      callback(nil, err)
      return
    end
    local session = result and result.session
    if type(session) ~= "table" then
      self.mutation_pending = false
      callback(nil, normalize_error("invalid_session", "conductor returned an invalid session reply"))
      return
    end
    self:_refresh_snapshot(function(refresh_error)
      self.mutation_pending = false
      callback(refresh_error and nil or vim.deepcopy(session), refresh_error)
    end)
  end)
  return true
end

function Controller:authenticate(backend_id, method_id, callback)
  callback = callback or noop
  if not self:_begin_mutation(callback) then
    return false
  end
  self.client:select_authentication(backend_id, method_id, function(result, err)
    self.mutation_pending = false
    if err then
      callback(nil, err)
      return
    end
    local catalog = result and result.catalog
    if type(catalog) ~= "table" then
      callback(nil, normalize_error("invalid_backend_catalog", "conductor returned an invalid backend catalog"))
      return
    end
    for index, existing in ipairs(self.catalogs) do
      if existing.backend == backend_id then
        self.catalogs[index] = vim.deepcopy(catalog)
        self.on_state(self:state())
        callback(vim.deepcopy(catalog), nil)
        return
      end
    end
    self.catalogs[#self.catalogs + 1] = vim.deepcopy(catalog)
    self.on_state(self:state())
    callback(vim.deepcopy(catalog), nil)
  end)
  return true
end

function Controller:stop()
  if self.stopped then
    return
  end
  self.stopped = true
  self.submission_pending = false
  self.store:set_connection("disconnected")
  self.client:stop()
end

M.Controller = Controller
return M