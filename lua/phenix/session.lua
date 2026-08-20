local Conductor = require("phenix.conductor")
local Controller = require("phenix.controller")
local ExecutionTreeView = require("phenix.execution_tree_view")
local ProjectionRenderer = require("phenix.projection_renderer")
local TargetSelection = require("phenix.target_selection")
local Ui = require("phenix.ui")

local M = {}
local Session = {}
Session.__index = Session

local terminal_states = {
  completed = true,
  failed = true,
  cancelled = true,
  interrupted = true,
}

local function conductor_command(options, cwd)
  local command = options.conductor_command
  if command == nil then
    command = vim.env.PHENIX_CONDUCTOR_COMMAND
  end
  if command == nil or command == "" then
    command = "phenix-conductor"
  end
  command = type(command) == "string" and { command } or vim.deepcopy(command)
  if options.conductor_cwd_arg ~= false then
    vim.list_extend(command, { "--cwd", cwd })
  end
  return command
end

local function conductor_client_factory(socket)
  if socket == nil then
    return nil
  end
  assert(type(socket) == "string" and vim.trim(socket) ~= "", "conductor_socket must be a non-empty path")
  local normalized = vim.fs.normalize(socket)
  return function(client_options)
    client_options.command = nil
    client_options.socket = normalized
    return Conductor.new(client_options)
  end
end

local function format_error(prefix, error_value)
  if not error_value then
    return prefix
  end
  return string.format("%s: %s", prefix, error_value.message or vim.inspect(error_value))
end

local function target_context(target)
  local context = { routing = "", backend = "", provider = "", model = "" }
  if type(target) ~= "table" then
    return context
  end
  if target.kind == "routed" then
    context.routing = "routing/" .. tostring(target.value or "")
  elseif target.kind == "fixed" and type(target.value) == "table" then
    context.backend = target.value.backend or ""
    context.provider = target.value.provider or ""
    context.model = target.value.model or ""
  end
  return context
end

function M.new(options)
  options = options or {}
  local cwd = vim.fs.normalize(options.cwd or vim.fn.getcwd())
  local session = setmetatable({
    cwd = cwd,
    options = vim.deepcopy(options),
    controller = nil,
    ui = nil,
    renderer = nil,
    execution_tree_view = nil,
    session_id = nil,
    ready = false,
    follow_ups = {},
    closed = false,
  }, Session)

  session.ui = Ui.new({
    width = options.width,
    input_height = options.input_height,
    input_height_min = options.input_height_min,
    input_height_max = options.input_height_max,
    image_height = options.image_height,
    image_width = options.image_width,
    image_paste_command = options.image_paste_command,
    follow_up_height = options.follow_up_height,
    follow_up_height_min = options.follow_up_height_min,
    follow_up_height_max = options.follow_up_height_max,
    chat_mode = options.chat_mode,
    on_submit = function(text, behavior, images)
      return session:submit(text, behavior, images)
    end,
    on_follow_up_edit = function(index, text)
      session:update_follow_up(index, text)
    end,
  })
  session.renderer = ProjectionRenderer.new(session.ui)
  session.execution_tree_view = ExecutionTreeView.new(session.ui)

  session.controller = Controller.new({
    command = options.conductor_socket and nil or conductor_command(options, cwd),
    client_factory = conductor_client_factory(options.conductor_socket),
    cwd = cwd,
    session_id = options.session_id,
    target = options.target,
    configured_target = options.configured_target,
    on_ready = function(summary)
      session.session_id = summary.id
      session.ready = true
      session.ui:set_context(target_context(summary.default_target))
      session:_sync_status()
      session:_sync_transcript_buffer_name()
      if options.on_ready then
        options.on_ready(session)
      end
    end,
    on_event = function(event)
      session:_execution_event(event)
    end,
    on_resync = function(blocks)
      session:_replace_projection(blocks)
    end,
    on_state = function()
      session:_sync_status()
    end,
    on_error = function(error_value)
      session.ui:append_error(format_error("conductor", error_value))
    end,
    on_exit = function(result)
      session.ready = false
      if not session.closed then
        session.ui:set_status(result.code == 0 and "Offline" or "Error")
      end
      if not session.closed and result.code ~= 0 then
        session.ui:append_error("conductor exited: " .. vim.inspect(result))
      end
    end,
  })

  return session
end

function Session:start()
  self.ui:mount(self.options)
  self.controller:start(function(_, error_value)
    if error_value then
      self.ready = false
      self.ui:set_status("Error")
    end
  end)
  return self
end

function Session:_sync_execution_tree()
  if self.closed or not self.execution_tree_view then
    return
  end
  self.execution_tree_view:render(self.session_id, self.controller.store.executions)
end

function Session:_sync_status()
  if self.closed then
    return
  end
  local state = self.controller:state()
  if state.connection == "error" then
    self.ui:set_status("Error")
  elseif state.connection ~= "connected" then
    self.ui:set_status("Offline")
  elseif state.activity == "running" then
    self.ui:set_status("Working")
  elseif self.ready then
    self.ui:set_status("Ready")
  end

  local summary = state.session
  if summary then
    self.ui:set_context(target_context(summary.default_target))
  end
  self:_sync_execution_tree()
end

function Session:_sync_transcript_buffer_name()
  if self.closed or not self.ui then
    return
  end
  local summary = self.controller:session()
  local name = summary and summary.name or nil
  self.ui:set_transcript_buffer_name(self.session_id, name)
end

function Session:_execution_event(event)
  if self.closed or event.session_id ~= self.session_id then
    return
  end

  -- The controller applies the canonical event to the semantic projection
  -- before this callback. Rendering consumes only that projection; the event
  -- is used solely to identify the semantic block that became dirty and for
  -- terminal follow-up scheduling below.
  self.renderer:sync(self.controller:projection_blocks(), event)

  local kind = event.kind or {}
  if kind.type == "execution_state_changed" and terminal_states[kind.state] then
    self.ui:finish_response()
    vim.schedule(function()
      if not self.closed and self.controller:activity_state() == "settled" then
        self:_send_next_follow_up()
      end
    end)
  end
end

function Session:_replace_projection(blocks)
  if self.closed then
    return
  end
  self.renderer:replace(blocks)
  self:_sync_execution_tree()
end

function Session:is_ready()
  return self.ready and not self.closed
end

---@return "running"|"settled"|nil
function Session:activity_state()
  if self.closed or not self.ready then
    return nil
  end
  return self.controller:activity_state()
end

function Session:prompt(text, label, images)
  text = vim.trim(text or "")
  if text == "" then
    return false
  end
  if #(images or {}) > 0 then
    vim.notify("Phenix: image submission is not yet part of the native conductor protocol", vim.log.levels.WARN)
    return false
  end
  if not self:is_ready() then
    vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
    return false
  end
  if self.controller:activity_state() == "running" then
    vim.notify("Phenix: current execution is still running", vim.log.levels.WARN)
    return false
  end

  local function submit_prompt()
    self.ui:set_status("Working")
    return self.controller:submit(text, function(_, error_value)
      if error_value then
        self.ui:append_error(format_error("submit failed", error_value))
        self:_sync_status()
      elseif label and label ~= "You" then
        -- User input itself is rendered from the conductor event. The label is
        -- frontend-only and intentionally does not mutate runtime state.
      end
    end)
  end

  local summary = self.controller:session()
  local target = summary and summary.default_target
  if type(target) ~= "table" or target.kind ~= "routed" or type(target.value) ~= "string" then
    return submit_prompt()
  end

  self:_ensure_routed_authentication(target.value, function(authentication_error)
    if authentication_error then
      if authentication_error.code ~= "authentication_cancelled" then
        self.ui:append_error(format_error("routing authentication failed", authentication_error))
      end
      self:_sync_status()
      return
    end
    submit_prompt()
  end)
  return true
end

function Session:_send_next_follow_up()
  if self.closed or not self.ready or self.controller:activity_state() == "running" then
    return
  end
  local text
  repeat
    text = table.remove(self.follow_ups, 1)
  until text == nil or vim.trim(text) ~= ""
  self.ui:set_follow_ups(self.follow_ups)
  if text then
    self:prompt(text, "Follow-up")
  end
end

function Session:update_follow_up(index, text)
  if self.closed or not self.follow_ups[index] then
    return false
  end
  self.follow_ups[index] = text
  return true
end

function Session:follow_up(text)
  text = vim.trim(text or "")
  if text == "" or not self:is_ready() then
    return false
  end
  if self.controller:activity_state() == "settled" then
    return self:prompt(text, "Follow-up")
  end
  self.follow_ups[#self.follow_ups + 1] = text
  self.ui:set_follow_ups(self.follow_ups)
  return true
end

function Session:steer(_)
  vim.notify("Phenix: steering is not exposed by the native conductor protocol", vim.log.levels.WARN)
  return false
end

function Session:submit(text, behavior, images)
  behavior = behavior or "send"
  if behavior == "steer" then
    return self:steer(text)
  elseif behavior == "follow_up" then
    if #(images or {}) > 0 then
      vim.notify("Phenix: queued image follow-ups are not supported", vim.log.levels.WARN)
      return false
    end
    return self:follow_up(text)
  end
  return self:prompt(text, nil, images)
end

function Session:cancel()
  if not self:is_ready() or self.controller:activity_state() ~= "running" then
    return false
  end
  self.follow_ups = {}
  self.ui:set_follow_ups(self.follow_ups)
  self.ui:set_status("Cancelling")
  return self.controller:cancel(function(_, error_value)
    if error_value then
      self.ui:append_error(format_error("cancel failed", error_value))
    end
    self:_sync_status()
  end)
end

function Session:toggle_chat_mode()
  return self.ui:toggle_chat_mode()
end

function Session:set_chat_mode(enabled)
  return self.ui:set_chat_mode(enabled)
end

function Session:_ensure_routed_authentication(profile_id, callback)
  return TargetSelection.ensure_routed_authentication(self, profile_id, callback)
end

function Session:select_model()
  return TargetSelection.select_model(self)
end

function Session:authenticate()
  return TargetSelection.authenticate(self)
end

function Session:restore()
  local sessions = {}
  for _, summary in pairs(self.controller.store.sessions) do
    sessions[#sessions + 1] = vim.deepcopy(summary)
  end
  table.sort(sessions, function(left, right)
    return tostring(left.id) < tostring(right.id)
  end)
  if #sessions == 0 then
    vim.notify("Phenix: conductor has no persisted sessions", vim.log.levels.WARN)
    return false
  end
  vim.ui.select(sessions, {
    prompt = "Restore Phenix session",
    format_item = function(summary)
      return summary.name or summary.id
    end,
  }, function(summary)
    if summary then
      self.controller:use_session(summary.id)
      self.session_id = summary.id
      self.ready = true
      self.ui:set_context(target_context(summary.default_target))
      self:_replace_projection(self.controller:projection_blocks())
      self:_sync_status()
      self:_sync_transcript_buffer_name()
      self.ui:show_transcript_for_session(summary.id)
    end
  end)
  return true
end

function Session:select_transcript()
  local sessions = {}
  for _, summary in pairs(self.controller.store.sessions) do
    sessions[#sessions + 1] = vim.deepcopy(summary)
  end
  table.sort(sessions, function(left, right)
    return tostring(left.id) < tostring(right.id)
  end)
  if #sessions == 0 then
    vim.notify("Phenix: conductor has no persisted sessions", vim.log.levels.WARN)
    return false
  end
  vim.ui.select(sessions, {
    prompt = "Select Phenix transcript",
    format_item = function(summary)
      return summary.name or summary.id
    end,
  }, function(summary)
    if summary then
      self.controller:use_session(summary.id)
      self.session_id = summary.id
      self.ready = true
      self.ui:set_context(target_context(summary.default_target))
      self:_replace_projection(self.controller:projection_blocks())
      self:_sync_status()
      self:_sync_transcript_buffer_name()
      self.ui:show_transcript_for_session(summary.id)
    end
  end)
  return true
end

function Session:toggle_info()
  if not self:is_ready() then
    return false
  end
  self:_sync_execution_tree()
  return self.execution_tree_view:toggle()
end

function Session:toggle_ui(options)
  self.ui:toggle(options)
end

function Session:toggle_maximize_input()
  self.ui:toggle_maximize()
end

function Session:focus_input()
  if not self.ui:is_visible() then
    self.ui:mount()
  else
    self.ui:focus_input()
  end
end

function Session:shutdown(close_ui)
  if self.closed then
    return
  end
  self.closed = true
  self.ready = false
  self.follow_ups = {}
  self.ui:set_follow_ups(self.follow_ups)
  if self.controller then
    self.controller:stop()
  end
  if close_ui ~= false and self.ui then
    self.ui:close()
  end
end

M.Session = Session
return M
