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
  return self.controller:state()
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

M.Session = Session
return M
