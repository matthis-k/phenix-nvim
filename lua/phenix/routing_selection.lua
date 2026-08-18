local Session = require("phenix.session").Session

local M = {}
local installed = false

local function error_message(prefix, value)
  if type(value) == "table" and value.message then
    return string.format("%s: %s", prefix, value.message)
  end
  return string.format("%s: %s", prefix, vim.inspect(value))
end

local function routing_profiles(result)
  if type(result) ~= "table" or result.type ~= "routing_catalog" or not vim.islist(result.profiles) then
    return nil, "invalid routing catalog reply"
  end

  local profiles = {}
  local seen = {}
  for _, profile in ipairs(result.profiles) do
    if type(profile) ~= "table" or type(profile.id) ~= "string" or vim.trim(profile.id) == "" then
      return nil, "routing catalog contains an invalid profile"
    end
    if not vim.islist(profile.providers) then
      return nil, "routing catalog profile has no provider requirements: " .. profile.id
    end
    local providers = {}
    local provider_seen = {}
    for _, provider in ipairs(profile.providers) do
      if type(provider) ~= "string" or vim.trim(provider) == "" then
        return nil, "routing catalog contains an invalid provider for " .. profile.id
      end
      if not provider_seen[provider] then
        provider_seen[provider] = true
        providers[#providers + 1] = provider
      end
    end
    table.sort(providers)
    if not seen[profile.id] then
      seen[profile.id] = true
      profiles[#profiles + 1] = {
        id = profile.id,
        providers = providers,
      }
    end
  end
  table.sort(profiles, function(left, right)
    return left.id < right.id
  end)
  return profiles
end

local function provider_groups(catalogs)
  local groups = {}

  local function group_for(provider)
    local group = groups[provider]
    if group then
      return group
    end
    group = {
      provider = provider,
      models = {},
      authentication_methods = {},
      authentication_method_keys = {},
      backends = {},
      backend_keys = {},
    }
    groups[provider] = group
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
      if type(method.provider) == "string" and method.provider ~= "" and method.selectable ~= false then
        local group = group_for(method.provider)
        local backend = method.backend or catalog.backend
        add_backend(group, backend)
        local key = string.format("%s\0%s\0%s", tostring(backend), tostring(method.id), tostring(method.kind))
        if not group.authentication_method_keys[key] then
          local choice = vim.deepcopy(method)
          choice._transport_backend = backend
          group.authentication_method_keys[key] = true
          group.authentication_methods[#group.authentication_methods + 1] = choice
        end
      end
    end
  end

  for _, group in pairs(groups) do
    table.sort(group.backends)
    table.sort(group.authentication_methods, function(left, right)
      return tostring(left.name or left.id) < tostring(right.name or right.id)
    end)
  end
  return groups
end

local function provider_ready(group)
  for _, model in ipairs(group and group.models or {}) do
    if type(model.target) == "table" and model.selectable ~= false then
      return true
    end
  end
  return false
end

local function refresh_provider(session, provider, callback)
  local group = provider_groups(session.controller:state().catalogs)[provider]
  if not group then
    callback({
      code = "unknown_provider",
      message = "routing profile requires provider not present in the conductor catalog: " .. provider,
    })
    return
  end
  local index = 1
  local function refresh_next()
    local backend = group.backends[index]
    if not backend then
      callback(nil)
      return
    end
    session.controller:refresh_backend(backend, function(_, refresh_error)
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

local function authenticate_provider(session, provider, callback)
  local group = provider_groups(session.controller:state().catalogs)[provider]
  if not group then
    callback({
      code = "unknown_provider",
      message = "routing profile requires provider not present in the conductor catalog: " .. provider,
    })
    return
  end
  if provider_ready(group) then
    callback(nil)
    return
  end
  if #group.authentication_methods == 0 then
    callback({
      code = "authentication_unavailable",
      message = string.format("routing requires authentication for %s, but no authentication method is available", provider),
    })
    return
  end

  local function authenticated()
    refresh_provider(session, provider, function(refresh_error)
      if refresh_error then
        callback(refresh_error)
        return
      end
      local refreshed = provider_groups(session.controller:state().catalogs)[provider]
      if not provider_ready(refreshed) then
        callback({
          code = "authentication_required",
          message = string.format("authentication for routing provider %s did not make any model selectable", provider),
        })
        return
      end
      callback(nil)
    end)
  end

  local function run_authentication(method, input)
    local backend = method._transport_backend or group.backends[1]
    if not backend then
      callback({
        code = "authentication_unavailable",
        message = string.format("routing provider %s has no authentication transport", provider),
      })
      return
    end
    session.controller:authenticate(backend, method.id, input, function(_, authentication_error)
      if authentication_error then
        callback(authentication_error)
        return
      end
      authenticated()
    end)
  end

  local function choose_method(method)
    if not method then
      callback({ code = "authentication_cancelled", message = "routing authentication was cancelled" })
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
        callback({ code = "authentication_cancelled", message = "routing authentication was cancelled" })
        return
      end
      run_authentication(method, { type = "api_key", secret = secret })
    end)
  end

  if #group.authentication_methods == 1 then
    choose_method(group.authentication_methods[1])
    return
  end
  vim.ui.select(group.authentication_methods, {
    prompt = string.format("Authenticate · %s", provider),
    format_item = function(method)
      return method.name or method.id
    end,
  }, choose_method)
end

local function ensure_profile_authentication(session, profile, callback)
  local index = 1
  local function authenticate_next()
    local provider = profile.providers[index]
    if not provider then
      callback(nil)
      return
    end
    authenticate_provider(session, provider, function(authentication_error)
      if authentication_error then
        callback(authentication_error)
        return
      end
      index = index + 1
      authenticate_next()
    end)
  end
  authenticate_next()
end

local function discover_profiles(session, callback)
  session.controller.client:get_routing_catalog(function(result, error_value)
    if error_value then
      callback(nil, error_value)
      return
    end
    local profiles, validation_error = routing_profiles(result)
    if validation_error then
      callback(nil, { code = "invalid_routing_catalog", message = validation_error })
      return
    end
    callback(profiles, nil)
  end)
end

local function find_profile(profiles, id)
  for _, profile in ipairs(profiles or {}) do
    if profile.id == id then
      return profile
    end
  end
  return nil
end

local function profile_missing_providers(session, profile)
  local groups = provider_groups(session.controller:state().catalogs)
  local missing = {}
  for _, provider in ipairs(profile.providers) do
    if not provider_ready(groups[provider]) then
      missing[#missing + 1] = provider
    end
  end
  return missing
end

local function profile_label(session, profile)
  local missing = profile_missing_providers(session, profile)
  if #missing == 0 then
    return "routing · " .. profile.id .. " · ready"
  end
  return string.format("routing · %s · auth required: %s", profile.id, table.concat(missing, ", "))
end

local function choose_route(session, profile)
  ensure_profile_authentication(session, profile, function(authentication_error)
    if authentication_error then
      if authentication_error.code ~= "authentication_cancelled" then
        session.ui:append_error(error_message("routing authentication failed", authentication_error))
      end
      return
    end
    session.controller:set_target({ kind = "routed", value = profile.id }, function(_, error_value)
      if error_value then
        session.ui:append_error(error_message("failed to select routing", error_value))
      end
    end)
  end)
end

local function open_model_or_routing_picker(session, direct_select, profiles)
  local ui_select = vim.ui.select
  local intercepted = false

  vim.ui.select = function(items, options, on_choice)
    if intercepted or type(options) ~= "table" or options.prompt ~= "Provider" then
      return ui_select(items, options, on_choice)
    end
    intercepted = true

    local choices = {}
    for _, profile in ipairs(profiles) do
      choices[#choices + 1] = { kind = "routing", profile = profile }
    end
    for _, provider in ipairs(items) do
      choices[#choices + 1] = { kind = "provider", value = provider }
    end

    local format_provider = options.format_item
    return ui_select(choices, {
      prompt = "Model or routing",
      format_item = function(choice)
        if choice.kind == "routing" then
          return profile_label(session, choice.profile)
        end
        if format_provider then
          return format_provider(choice.value)
        end
        return tostring(choice.value)
      end,
    }, function(choice, index)
      if not choice then
        return
      end
      if choice.kind == "routing" then
        choose_route(session, choice.profile)
        return
      end
      on_choice(choice.value, index)
    end)
  end

  local ok, result = xpcall(function()
    return direct_select(session)
  end, debug.traceback)
  vim.ui.select = ui_select
  if not ok then
    error(result)
  end
  return result
end

function M.install()
  if installed then
    return
  end
  installed = true

  local direct_select = Session.select_model
  local direct_prompt = Session.prompt

  function Session:select_model()
    if not self:is_ready() then
      return direct_select(self)
    end

    discover_profiles(self, function(profiles, error_value)
      if error_value then
        self.ui:append_error(error_message("routing discovery failed", error_value))
        return
      end
      if #profiles == 0 then
        direct_select(self)
        return
      end
      open_model_or_routing_picker(self, direct_select, profiles)
    end)
    return true
  end

  function Session:prompt(...)
    if not self:is_ready() then
      return direct_prompt(self, ...)
    end
    local summary = self.controller:session()
    local target = summary and summary.default_target
    if type(target) ~= "table" or target.kind ~= "routed" or type(target.value) ~= "string" then
      return direct_prompt(self, ...)
    end

    local arguments = { ... }
    discover_profiles(self, function(profiles, discovery_error)
      if discovery_error then
        self.ui:append_error(error_message("routing discovery failed", discovery_error))
        return
      end
      local profile = find_profile(profiles, target.value)
      if not profile then
        self.ui:append_error("routing discovery failed: selected profile disappeared: " .. target.value)
        return
      end
      ensure_profile_authentication(self, profile, function(authentication_error)
        if authentication_error then
          if authentication_error.code ~= "authentication_cancelled" then
            self.ui:append_error(error_message("routing authentication failed", authentication_error))
          end
          return
        end
        direct_prompt(self, unpack(arguments))
      end)
    end)
    return true
  end
end

return M
