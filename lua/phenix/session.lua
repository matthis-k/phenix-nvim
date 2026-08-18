local Conductor = require("phenix.conductor")
local Controller = require("phenix.controller")
local ExecutionTreeView = require("phenix.execution_tree_view")
local ProjectionRenderer = require("phenix.projection_renderer")
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
    on_ready = function(summary)
      session.session_id = summary.id
      session.ready = true
      session.ui:set_context(target_context(summary.default_target))
      session:_sync_status()
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

local function provider_groups(catalogs)
  local groups = {}
  local ordered = {}

  local function group_for(provider)
    local group = groups[provider]
    if group then
      return group
    end
    group = {
      key = provider,
      provider = provider,
      models = {},
      authentication_methods = {},
      authentication_method_keys = {},
      backends = {},
      backend_keys = {},
    }
    groups[provider] = group
    ordered[#ordered + 1] = group
    return group
  end

  local function add_backend(group, backend)
    if type(backend) ~= "string" or backend == "" or group.backend_keys[backend] then
      return
    end
    group.backend_keys[backend] = true
    group.backends[#group.backends + 1] = backend
  end

  for _, catalog in ipairs(catalogs or {}) do
    for _, model in ipairs(catalog.models or {}) do
      local target = model.target
      if type(target) == "table" and type(target.provider) == "string" and target.provider ~= "" then
        local group = group_for(target.provider)
        add_backend(group, target.backend or catalog.backend)
        group.models[#group.models + 1] = model
      end
    end
    for _, method in ipairs(catalog.authentication_methods or {}) do
      if type(method.provider) == "string" and method.provider ~= "" then
        local group = group_for(method.provider)
        local backend = method.backend or catalog.backend
        add_backend(group, backend)
        if method.selectable ~= false then
          local key = string.format("%s\0%s", tostring(method.id or ""), tostring(method.kind or ""))
          if not group.authentication_method_keys[key] then
            local choice = vim.deepcopy(method)
            choice._transport_backend = backend
            group.authentication_method_keys[key] = true
            group.authentication_methods[#group.authentication_methods + 1] = choice
          end
        end
      end
    end
  end

  for _, group in ipairs(ordered) do
    table.sort(group.backends)
    table.sort(group.authentication_methods, function(left, right)
      return tostring(left.name or left.id) < tostring(right.name or right.id)
    end)
  end
  table.sort(ordered, function(left, right)
    return left.provider < right.provider
  end)
  return ordered
end

local function find_provider_group(catalogs, selected)
  for _, group in ipairs(provider_groups(catalogs)) do
    if group.key == selected.key then
      return group
    end
  end
  return nil
end

local function selectable_models(group)
  local models = {}
  for _, model in ipairs(group and group.models or {}) do
    if type(model.target) == "table" and model.selectable ~= false then
      models[#models + 1] = model
    end
  end
  table.sort(models, function(left, right)
    local left_name = tostring(left.name or left.target.model)
    local right_name = tostring(right.name or right.target.model)
    if left_name == right_name then
      return tostring(left.target.backend or "") < tostring(right.target.backend or "")
    end
    return left_name < right_name
  end)
  return models
end

local function authentication_summary(group)
  local labels = {}
  local seen = {}
  for _, method in ipairs(group.authentication_methods or {}) do
    local label = method.kind == "api_key" and "API key" or method.name or method.id or method.kind
    label = tostring(label)
    if label ~= "" and not seen[label] then
      seen[label] = true
      labels[#labels + 1] = label
    end
  end
  return table.concat(labels, " / ")
end

local function provider_label(group)
  local auth = authentication_summary(group)
  local ready = #selectable_models(group) > 0
  if auth == "" then
    return string.format("%s · %s", group.provider, ready and "ready" or "unavailable")
  end
  if ready then
    return string.format("%s · ready · auth: %s", group.provider, auth)
  end
  return string.format("%s · auth required · %s", group.provider, auth)
end

function Session:_refresh_provider(selected_provider, callback)
  local group = find_provider_group(self.controller:state().catalogs, selected_provider)
  if not group then
    callback({ message = "selected provider disappeared from the conductor catalog" })
    return
  end
  if #group.backends == 0 then
    callback(nil)
    return
  end

  local index = 1
  local function refresh_next()
    local backend = group.backends[index]
    if not backend then
      callback(nil)
      return
    end
    self.controller:refresh_backend(backend, function(_, refresh_error)
      if refresh_error then
        callback(refresh_error)
        return
      end
      index = index + 1
      refresh_next()
    end)
  end
  refresh_next()
end

function Session:select_model()
  if not self:is_ready() then
    vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
    return false
  end

  local function open_models(selected_provider)
    local group = find_provider_group(self.controller:state().catalogs, selected_provider)
    if not group then
      self.ui:append_error("model selection failed: selected provider disappeared from the conductor catalog")
      return
    end
    local models = selectable_models(group)
    if #models == 0 then
      self.ui:append_error(string.format("model selection failed: provider %s exposes no selectable models", group.provider))
      return
    end
    vim.ui.select(models, {
      prompt = string.format("Model · %s", group.provider),
      format_item = function(model)
        return model.name or tostring(model.target.model)
      end,
    }, function(model)
      if not model then
        return
      end
      local target = { kind = "fixed", value = vim.deepcopy(model.target) }
      self.controller:set_target(target, function(summary, error_value)
        if error_value then
          self.ui:append_error(format_error("failed to select model", error_value))
          return
        end
        self.ui:set_context(target_context(summary.default_target))
      end)
    end)
  end

  local function refresh_and_open_models(selected_provider)
    self:_refresh_provider(selected_provider, function(refresh_error)
      if refresh_error then
        self.ui:append_error(format_error("model discovery failed", refresh_error))
        return
      end
      open_models(selected_provider)
    end)
  end

  local function authenticate_provider(selected_provider)
    local group = find_provider_group(self.controller:state().catalogs, selected_provider)
    if not group then
      self.ui:append_error("authentication failed: selected provider disappeared from the conductor catalog")
      return
    end
    local methods = group.authentication_methods
    if #methods == 0 then
      self.ui:append_error(string.format("authentication required for %s, but no authentication method is available", group.provider))
      return
    end

    local function run_authentication(method, input)
      local backend = method._transport_backend or group.backends[1]
      if not backend then
        self.ui:append_error(string.format("authentication failed: provider %s has no authentication transport", group.provider))
        return
      end
      self.controller:authenticate(backend, method.id, input, function(_, authentication_error)
        if authentication_error then
          self.ui:append_error(format_error("authentication failed", authentication_error))
          return
        end
        refresh_and_open_models(selected_provider)
      end)
    end

    local function choose_method(method)
      if not method then
        return
      end
      if method.kind ~= "api_key" then
        run_authentication(method, nil)
        return
      end
      vim.schedule(function()
        local secret = vim.fn.inputsecret(string.format("%s: ", method.name or method.id))
        vim.cmd("redraw")
        if type(secret) ~= "string" or vim.trim(secret) == "" then
          return
        end
        run_authentication(method, { type = "api_key", secret = secret })
      end)
    end

    if #methods == 1 then
      choose_method(methods[1])
      return
    end
    vim.ui.select(methods, {
      prompt = string.format("Authenticate · %s", group.provider),
      format_item = function(method)
        return method.name or method.id
      end,
    }, choose_method)
  end

  local function choose_provider(selected_provider)
    if not selected_provider then
      return
    end
    local group = find_provider_group(self.controller:state().catalogs, selected_provider)
    if not group then
      self.ui:append_error("model selection failed: selected provider disappeared from the conductor catalog")
      return
    end
    if #selectable_models(group) == 0 then
      authenticate_provider(selected_provider)
      return
    end
    refresh_and_open_models(selected_provider)
  end

  self.controller.client:get_routing_catalog(function(result, routing_error)
    if routing_error then
      self.ui:append_error(format_error("routing discovery failed", routing_error))
      return
    end

    local profiles = {}
    for _, profile in ipairs(result and result.profiles or {}) do
      if type(profile) == "string" and profile ~= "" then
        profiles[#profiles + 1] = profile
      end
    end
    table.sort(profiles)

    local providers = provider_groups(self.controller:state().catalogs)
    if #profiles == 0 then
      if #providers == 0 then
        vim.notify("Phenix: conductor exposes no selectable targets", vim.log.levels.WARN)
        return
      end
      vim.ui.select(providers, {
        prompt = "Provider",
        format_item = provider_label,
      }, choose_provider)
      return
    end

    local choices = {}
    for _, profile in ipairs(profiles) do
      choices[#choices + 1] = { kind = "routing", value = profile }
    end
    for _, provider in ipairs(providers) do
      choices[#choices + 1] = { kind = "provider", value = provider }
    end

    vim.ui.select(choices, {
      prompt = "Model or routing",
      format_item = function(choice)
        if choice.kind == "routing" then
          return "Routing · " .. choice.value
        end
        return "Provider · " .. provider_label(choice.value)
      end,
    }, function(choice)
      if not choice then
        return
      end
      if choice.kind == "provider" then
        choose_provider(choice.value)
        return
      end
      if choice.kind ~= "routing" then
        self.ui:append_error("model selection failed: unknown target choice")
        return
      end
      self.controller:set_target({ kind = "routed", value = choice.value }, function(summary, error_value)
        if error_value then
          self.ui:append_error(format_error("failed to select routing profile", error_value))
          return
        end
        self.ui:set_context(target_context(summary.default_target))
      end)
    end)
  end)
  return true
end
function Session:authenticate()
  if not self:is_ready() then
    vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
    return false
  end

  local providers = {}
  for _, provider in ipairs(provider_groups(self.controller:state().catalogs)) do
    if #provider.authentication_methods > 0 then
      providers[#providers + 1] = provider
    end
  end
  if #providers == 0 then
    vim.notify("Phenix: conductor exposes no selectable authentication methods", vim.log.levels.WARN)
    return false
  end

  local function choose_provider(provider)
    if not provider then
      return
    end
    local group = find_provider_group(self.controller:state().catalogs, provider)
    if not group then
      self.ui:append_error("authentication failed: selected provider disappeared from the conductor catalog")
      return
    end

    local function authenticate_method(method, input)
      local backend = method._transport_backend or group.backends[1]
      if not backend then
        self.ui:append_error(string.format("authentication failed: provider %s has no authentication transport", group.provider))
        return
      end
      self.controller:authenticate(backend, method.id, input, function(_, error_value)
        if error_value then
          self.ui:append_error(format_error("authentication failed", error_value))
        end
      end)
    end

    local function choose_method(method)
      if not method then
        return
      end
      if method.kind ~= "api_key" then
        authenticate_method(method, nil)
        return
      end
      vim.schedule(function()
        local secret = vim.fn.inputsecret(string.format("%s: ", method.name or method.id))
        vim.cmd("redraw")
        if type(secret) ~= "string" or vim.trim(secret) == "" then
          return
        end
        authenticate_method(method, {
          type = "api_key",
          secret = secret,
        })
      end)
    end

    if #group.authentication_methods == 1 then
      choose_method(group.authentication_methods[1])
      return
    end
    vim.ui.select(group.authentication_methods, {
      prompt = string.format("Authenticate · %s", group.provider),
      format_item = function(method)
        return method.name or method.id
      end,
    }, choose_method)
  end

  vim.ui.select(providers, {
    prompt = "Authenticate provider",
    format_item = provider_label,
  }, choose_provider)
  return true
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
    end
  end)
  return true
end

function Session:select_transcript()
  return self:restore()
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