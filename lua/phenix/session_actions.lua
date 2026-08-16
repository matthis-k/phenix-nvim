require("phenix.controller_actions")

local Session = require("phenix.session").Session

local M = {}

local function default_callback(session, action)
  return function(_, err)
    if err and session.ui then
      session.ui:append_error(string.format("%s failed: %s", action, err.message or vim.inspect(err)))
    end
  end
end

local function switch_to(session, summary)
  local selected, err = session.controller:use_session(summary.id)
  if not selected then
    return nil, err
  end
  session.session_id = summary.id
  session.ready = true
  session:_replace_projection(session.controller:projection_blocks())
  session:_sync_status()
  return selected, nil
end

function Session:state()
  if self.closed then
    return nil
  end
  local state = self.controller:state()
  state.callables = vim.deepcopy(self.controller.callables or {})
  return state
end

function Session:callables()
  if self.closed then
    return {}
  end
  return vim.deepcopy(self.controller.callables or {})
end

function Session:set_target(target, callback)
  callback = callback or default_callback(self, "target update")
  if not self:is_ready() then
    callback(nil, { code = "session_not_ready", message = "session is not ready" })
    return false
  end
  return self.controller:set_target(target, function(summary, err)
    if not err then
      self:_sync_status()
    end
    callback(summary, err)
  end)
end

function Session:fork(name, callback)
  callback = callback or default_callback(self, "session fork")
  if not self:is_ready() then
    callback(nil, { code = "session_not_ready", message = "session is not ready" })
    return false
  end
  if name == nil then
    local current = self.controller:session()
    local base = current and (current.name or current.id) or "Phenix"
    name = base .. " (fork)"
  end
  return self.controller:fork(name, function(summary, err)
    if err then
      callback(nil, err)
      return
    end
    local selected, select_error = switch_to(self, summary)
    callback(selected, select_error)
  end)
end

function Session:rename(name, callback)
  callback = callback or default_callback(self, "session rename")
  if not self:is_ready() then
    callback(nil, { code = "session_not_ready", message = "session is not ready" })
    return false
  end
  return self.controller:rename(name, function(summary, err)
    if not err then
      self:_sync_status()
    end
    callback(summary, err)
  end)
end

function Session:refresh_backend(backend_id, callback)
  callback = callback or default_callback(self, "backend refresh")
  if not self:is_ready() then
    callback(nil, { code = "session_not_ready", message = "session is not ready" })
    return false
  end
  return self.controller:refresh_backend(backend_id, callback)
end

function Session:refresh_catalogs(callback)
  callback = callback or default_callback(self, "catalog refresh")
  if not self:is_ready() then
    callback(nil, { code = "session_not_ready", message = "session is not ready" })
    return false
  end
  return self.controller:refresh_catalogs(callback)
end

function Session:refresh_callables(callback)
  callback = callback or default_callback(self, "callable catalog refresh")
  if not self:is_ready() then
    callback(nil, { code = "session_not_ready", message = "session is not ready" })
    return false
  end
  return self.controller:refresh_callables(callback)
end

function Session:run_callable(callable_id, objective, callback)
  callback = callback or default_callback(self, "callable execution")
  if not self:is_ready() then
    callback(nil, { code = "session_not_ready", message = "session is not ready" })
    return false
  end

  if #(self.controller.callables or {}) == 0 then
    return self:refresh_callables(function(_, catalog_error)
      if catalog_error then
        callback(nil, catalog_error)
        return
      end
      self:run_callable(callable_id, objective, callback)
    end)
  end

  self.ui:set_status("Working")
  return self.controller:start_callable(callable_id, objective, function(execution, err)
    if err then
      self:_sync_status()
    end
    callback(execution, err)
  end)
end

function Session:select_callable()
  if not self:is_ready() then
    return false
  end
  if #(self.controller.callables or {}) == 0 then
    return self:refresh_callables(function(_, err)
      if not err then
        self:select_callable()
      end
    end)
  end

  local choices = {}
  for _, descriptor in ipairs(self:callables()) do
    if descriptor.kind == "agent" or descriptor.kind == "workflow" then
      choices[#choices + 1] = descriptor
    end
  end
  if #choices == 0 then
    vim.notify("Phenix: conductor exposes no startable callables", vim.log.levels.WARN)
    return false
  end

  vim.ui.select(choices, {
    prompt = "Callable",
    format_item = function(descriptor)
      local description = descriptor.description and vim.trim(descriptor.description) or ""
      local label = string.format("%s · %s", descriptor.kind, descriptor.id)
      return description ~= "" and (label .. " — " .. description) or label
    end,
  }, function(descriptor)
    if not descriptor then
      return
    end
    vim.ui.input({ prompt = string.format("Objective for %s", descriptor.id) }, function(objective)
      if objective ~= nil and vim.trim(objective) ~= "" then
        self:run_callable(descriptor.id, objective)
      end
    end)
  end)
  return true
end

M.Session = Session
return M
