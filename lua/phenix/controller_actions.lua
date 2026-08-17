local M = {}

local terminal_states = {
  completed = true,
  failed = true,
  cancelled = true,
  interrupted = true,
}

local function noop() end

local function error_value(code, message)
  return { code = code, message = tostring(message) }
end

local function execution_number(id)
  return tonumber(tostring(id or ""):match("(%d+)$")) or -1
end

local function install_catalog(controller, catalog)
  if type(catalog) ~= "table" or type(catalog.backend) ~= "string" then
    return nil, error_value("invalid_backend_catalog", "conductor returned an invalid backend catalog")
  end
  for index, existing in ipairs(controller.catalogs) do
    if existing.backend == catalog.backend then
      controller.catalogs[index] = vim.deepcopy(catalog)
      return vim.deepcopy(catalog), nil
    end
  end
  controller.catalogs[#controller.catalogs + 1] = vim.deepcopy(catalog)
  return vim.deepcopy(catalog), nil
end

local function validate_callable_catalog(result)
  if type(result) ~= "table" or result.type ~= "callable_catalog" or type(result.callables) ~= "table" then
    return nil, error_value("invalid_callable_catalog", "conductor returned an invalid callable catalog")
  end
  local callables = {}
  for _, descriptor in ipairs(result.callables) do
    if type(descriptor) ~= "table"
      or type(descriptor.id) ~= "string"
      or (descriptor.kind ~= "tool" and descriptor.kind ~= "agent" and descriptor.kind ~= "workflow")
    then
      return nil, error_value("invalid_callable_catalog", "conductor callable catalog contains an invalid descriptor")
    end
    callables[#callables + 1] = vim.deepcopy(descriptor)
  end
  table.sort(callables, function(left, right)
    return left.id < right.id
  end)
  return callables, nil
end

local function callable_descriptor(controller, callable_id)
  for _, descriptor in ipairs(controller.callables or {}) do
    if descriptor.id == callable_id then
      return descriptor
    end
  end
  return nil
end

function M.attach(Controller, _dependencies)
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

  function Controller:_begin_mutation(callback, allow_during_refresh)
    if self.mutation_pending or self.resyncing or (self.refreshing and not allow_during_refresh) then
      callback(nil, error_value("frontend_busy", "frontend state synchronization is already in progress"))
      return false
    end
    self.mutation_pending = true
    return true
  end

  function Controller:submit(text, callback)
    callback = callback or noop
    if self:execution() then
      callback(nil, error_value("execution_active", "the session already has an active execution"))
      return false
    end
    if not self:_begin_mutation(callback, true) then
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
        callback(nil, error_value("invalid_execution", "conductor returned an invalid execution reply"))
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
      callback(nil, error_value("no_active_execution", "there is no active execution to cancel"))
      return false
    end
    if not self:_begin_mutation(callback, true) then
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
      callback(nil, error_value("invalid_target", "target must be a typed fixed or routed target"))
      return false
    end
    if not self:_begin_mutation(callback, true) then
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
        callback(nil, error_value("invalid_session", "conductor returned an invalid session reply"))
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
      local catalog, catalog_error = install_catalog(self, result and result.catalog)
      if catalog_error then
        callback(nil, catalog_error)
        return
      end
      self.on_state(self:state())
      callback(catalog, nil)
    end)
    return true
  end

  function Controller:fork(name, callback)
    callback = callback or noop
    if not self.session_id then
      callback(nil, error_value("no_session", "there is no selected session to fork"))
      return false
    end
    if not self:_begin_mutation(callback, true) then
      return false
    end

    self.client:fork_session(self.session_id, name, function(result, err)
      if err then
        self.mutation_pending = false
        callback(nil, err)
        return
      end
      local session = result and result.session
      if type(session) ~= "table" or type(session.id) ~= "string" then
        self.mutation_pending = false
        callback(nil, error_value("invalid_session", "conductor returned an invalid forked session"))
        return
      end
      self:_refresh_snapshot(function(refresh_error)
        self.mutation_pending = false
        callback(refresh_error and nil or vim.deepcopy(self.store.sessions[session.id] or session), refresh_error)
      end)
    end)
    return true
  end

  function Controller:rename(name, callback)
    callback = callback or noop
    if type(name) ~= "string" or vim.trim(name) == "" then
      callback(nil, error_value("invalid_name", "session name must be a non-empty string"))
      return false
    end
    if not self.session_id then
      callback(nil, error_value("no_session", "there is no selected session to rename"))
      return false
    end
    if not self:_begin_mutation(callback, true) then
      return false
    end

    self.client:rename_session(self.session_id, name, function(result, err)
      if err then
        self.mutation_pending = false
        callback(nil, err)
        return
      end
      local session = result and result.session
      if type(session) ~= "table" or type(session.id) ~= "string" then
        self.mutation_pending = false
        callback(nil, error_value("invalid_session", "conductor returned an invalid renamed session"))
        return
      end
      self:_refresh_snapshot(function(refresh_error)
        self.mutation_pending = false
        callback(refresh_error and nil or vim.deepcopy(self.store.sessions[session.id] or session), refresh_error)
      end)
    end)
    return true
  end

  function Controller:refresh_backend(backend_id, callback)
    callback = callback or noop
    if type(backend_id) ~= "string" or vim.trim(backend_id) == "" then
      callback(nil, error_value("invalid_backend", "backend id must be a non-empty string"))
      return false
    end
    if not self:_begin_mutation(callback) then
      return false
    end

    self.client:refresh_backend_catalog(backend_id, function(result, err)
      self.mutation_pending = false
      if err then
        callback(nil, err)
        return
      end
      local catalog, catalog_error = install_catalog(self, result and result.catalog)
      if catalog_error then
        callback(nil, catalog_error)
        return
      end
      self.on_state(self:state())
      callback(catalog, nil)
    end)
    return true
  end

  function Controller:refresh_catalogs(callback)
    callback = callback or noop
    if not self:_begin_mutation(callback) then
      return false
    end

    local backend_ids = {}
    for _, catalog in ipairs(self.catalogs) do
      if type(catalog.backend) == "string" then
        backend_ids[#backend_ids + 1] = catalog.backend
      end
    end
    table.sort(backend_ids)

    if #backend_ids == 0 then
      self:_refresh_snapshot(function(err)
        self.mutation_pending = false
        callback(err and nil or vim.deepcopy(self.catalogs), err)
      end)
      return true
    end

    local index = 1
    local function refresh_next()
      local backend_id = backend_ids[index]
      if not backend_id then
        self.mutation_pending = false
        self.on_state(self:state())
        callback(vim.deepcopy(self.catalogs), nil)
        return
      end
      self.client:refresh_backend_catalog(backend_id, function(result, err)
        if err then
          self.mutation_pending = false
          callback(nil, err)
          return
        end
        local _, catalog_error = install_catalog(self, result and result.catalog)
        if catalog_error then
          self.mutation_pending = false
          callback(nil, catalog_error)
          return
        end
        index = index + 1
        refresh_next()
      end)
    end

    refresh_next()
    return true
  end

  function Controller:refresh_callables(callback)
    callback = callback or noop
    self.client:get_callable_catalog(function(result, err)
      if err then
        callback(nil, err)
        return
      end
      local callables, catalog_error = validate_callable_catalog(result)
      if catalog_error then
        callback(nil, catalog_error)
        return
      end
      self.callables = callables
      self.on_state(self:state())
      callback(vim.deepcopy(callables), nil)
    end)
    return true
  end

  function Controller:start_callable(callable_id, objective, callback)
    callback = callback or noop
    if type(callable_id) ~= "string" or vim.trim(callable_id) == "" then
      callback(nil, error_value("invalid_callable", "callable id must be a non-empty string"))
      return false
    end
    if type(objective) ~= "string" or vim.trim(objective) == "" then
      callback(nil, error_value("invalid_objective", "callable objective must be a non-empty string"))
      return false
    end
    if self:execution() then
      callback(nil, error_value("execution_active", "the session already has an active execution"))
      return false
    end

    local descriptor = callable_descriptor(self, callable_id)
    if not descriptor then
      callback(nil, error_value("unknown_callable", "callable is not present in the conductor catalog: " .. callable_id))
      return false
    end
    if descriptor.kind == "tool" then
      callback(nil, error_value("callable_not_startable", "tools cannot be started as top-level executions"))
      return false
    end
    if not self:_begin_mutation(callback, true) then
      return false
    end

    self.submission_pending = true
    self.on_state(self:state())
    self.client:start_callable(self.session_id, callable_id, objective, function(result, err)
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
        callback(nil, error_value("invalid_execution", "conductor returned an invalid callable execution reply"))
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

  return Controller
end

M.install_catalog = install_catalog
M.validate_callable_catalog = validate_callable_catalog
return M
