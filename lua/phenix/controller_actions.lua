local Controller = require("phenix.controller").Controller

local M = {}

local function noop() end

local function error_value(code, message)
  return { code = code, message = tostring(message) }
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

function Controller:fork(name, callback)
  callback = callback or noop
  if not self.session_id then
    callback(nil, error_value("no_session", "there is no selected session to fork"))
    return false
  end
  if not self:_begin_mutation(callback) then
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
  if not self:_begin_mutation(callback) then
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

M.install_catalog = install_catalog
return M
