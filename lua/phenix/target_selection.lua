local M = {}

local function format_error(prefix, error_value)
  if not error_value then
    return prefix
  end
  return string.format("%s: %s", prefix, error_value.message or vim.inspect(error_value))
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

local function find_provider_group(session, selected)
  local selected_key = type(selected) == "table" and selected.key or selected
  for _, group in ipairs(provider_groups(session.controller:state().catalogs)) do
    if group.key == selected_key then
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

local function routing_profiles(result)
  if type(result) ~= "table" or result.type ~= "routing_catalog" or not vim.islist(result.profiles) then
    return nil, { code = "invalid_routing_catalog", message = "conductor returned an invalid routing catalog" }
  end
  local profiles = {}
  local seen = {}
  for _, profile in ipairs(result.profiles) do
    if type(profile) ~= "table" or type(profile.id) ~= "string" or vim.trim(profile.id) == "" then
      return nil, { code = "invalid_routing_catalog", message = "routing catalog contains an invalid profile" }
    end
    if not vim.islist(profile.providers) then
      return nil, {
        code = "invalid_routing_catalog",
        message = "routing profile has no provider requirements: " .. profile.id,
      }
    end
    local providers = {}
    local provider_seen = {}
    for _, provider in ipairs(profile.providers) do
      if type(provider) ~= "string" or vim.trim(provider) == "" then
        return nil, {
          code = "invalid_routing_catalog",
          message = "routing profile contains an invalid provider: " .. profile.id,
        }
      end
      if not provider_seen[provider] then
        provider_seen[provider] = true
        providers[#providers + 1] = provider
      end
    end
    table.sort(providers)
    if not seen[profile.id] then
      seen[profile.id] = true
      profiles[#profiles + 1] = { id = profile.id, providers = providers }
    end
  end
  table.sort(profiles, function(left, right)
    return left.id < right.id
  end)
  return profiles, nil
end

local function find_routing_profile(profiles, profile_id)
  for _, profile in ipairs(profiles or {}) do
    if profile.id == profile_id then
      return profile
    end
  end
  return nil
end

local function missing_routing_providers(session, profile)
  local missing = {}
  for _, provider in ipairs(profile.providers or {}) do
    local group = find_provider_group(session, provider)
    if not group or #selectable_models(group) == 0 then
      missing[#missing + 1] = provider
    end
  end
  return missing
end

local function routing_label(session, profile)
  local missing = missing_routing_providers(session, profile)
  if #missing == 0 then
    return "Routing · " .. profile.id .. " · ready"
  end
  return string.format("Routing · %s · auth required: %s", profile.id, table.concat(missing, ", "))
end

local function refresh_provider(session, selected_provider, callback)
  local group = find_provider_group(session, selected_provider)
  if not group then
    callback({ code = "unknown_provider", message = "selected provider disappeared from the conductor catalog" })
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

local function finish_authentication(session, group, require_model, callback)
  if not require_model then
    callback(nil)
    return
  end
  refresh_provider(session, group, function(refresh_error)
    if refresh_error then
      callback(refresh_error)
      return
    end
    local refreshed = find_provider_group(session, group)
    if not refreshed or #selectable_models(refreshed) == 0 then
      callback({
        code = "authentication_required",
        message = string.format("authentication for %s did not make a model selectable", group.provider),
      })
      return
    end
    callback(nil)
  end)
end

local function run_authentication(session, group, method, require_model, callback)
  local backend = method._transport_backend or group.backends[1]
  if not backend then
    callback({
      code = "authentication_unavailable",
      message = string.format("provider %s has no authentication transport", group.provider),
    })
    return
  end
  session.controller:authenticate(backend, method.id, nil, function(_, authentication_error)
    if authentication_error then
      callback(authentication_error)
      return
    end
    finish_authentication(session, group, require_model, callback)
  end)
end

local function run_api_key_authentication(session, group, method, require_model, callback)
  vim.schedule(function()
    local secret = vim.fn.inputsecret(string.format("%s: ", method.name or method.id))
    vim.cmd("redraw")
    if type(secret) ~= "string" or vim.trim(secret) == "" then
      callback({ code = "authentication_cancelled", message = "authentication was cancelled" })
      return
    end
    local backend = method._transport_backend or group.backends[1]
    if not backend then
      callback({
        code = "authentication_unavailable",
        message = string.format("provider %s has no authentication transport", group.provider),
      })
      return
    end
    session.controller:authenticate(backend, method.id, { type = "api_key", secret = secret }, function(_, authentication_error)
      if authentication_error then
        callback(authentication_error)
        return
      end
      finish_authentication(session, group, require_model, callback)
    end)
  end)
end

local function authenticate_with_method(session, group, method, require_model, callback)
  if not method then
    callback({ code = "authentication_cancelled", message = "authentication was cancelled" })
    return
  end
  if method.kind == "api_key" then
    run_api_key_authentication(session, group, method, require_model, callback)
    return
  end
  run_authentication(session, group, method, require_model, callback)
end

local function authenticate_provider(session, selected_provider, require_model, callback)
  local group = find_provider_group(session, selected_provider)
  if not group then
    callback({
      code = "unknown_provider",
      message = "provider disappeared from the conductor catalog: " .. tostring(type(selected_provider) == "table" and selected_provider.key or selected_provider),
    })
    return
  end
  if require_model and #selectable_models(group) > 0 then
    callback(nil)
    return
  end
  if #group.authentication_methods == 0 then
    callback({
      code = "authentication_unavailable",
      message = string.format("authentication required for %s, but no authentication method is available", group.provider),
    })
    return
  end

  local function choose_method(method)
    authenticate_with_method(session, group, method, require_model, callback)
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

local function authenticate_routing_profile(session, profile, callback)
  local index = 1
  local function authenticate_next()
    local provider = profile.providers[index]
    if not provider then
      callback(nil)
      return
    end
    authenticate_provider(session, provider, true, function(authentication_error)
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

function M.ensure_routed_authentication(session, profile_id, callback)
  session.controller.client:get_routing_catalog(function(result, routing_error)
    if routing_error then
      callback(routing_error)
      return
    end
    local profiles, catalog_error = routing_profiles(result)
    if catalog_error then
      callback(catalog_error)
      return
    end
    local profile = find_routing_profile(profiles, profile_id)
    if not profile then
      callback({
        code = "unknown_routing_profile",
        message = "selected routing profile disappeared: " .. tostring(profile_id),
      })
      return
    end
    authenticate_routing_profile(session, profile, callback)
  end)
end

function M.select_model(session)
  if not session:is_ready() then
    vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
    return false
  end

  local function open_models(selected_provider)
    local group = find_provider_group(session, selected_provider)
    if not group then
      session.ui:append_error("model selection failed: selected provider disappeared from the conductor catalog")
      return
    end
    local models = selectable_models(group)
    if #models == 0 then
      session.ui:append_error(string.format("model selection failed: provider %s exposes no selectable models", group.provider))
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
      session.controller:set_target({ kind = "fixed", value = vim.deepcopy(model.target) }, function(_, error_value)
        if error_value then
          session.ui:append_error(format_error("failed to select model", error_value))
          return
        end
        session:_sync_status()
      end)
    end)
  end

  local function choose_provider(selected_provider)
    if not selected_provider then
      return
    end
    local group = find_provider_group(session, selected_provider)
    if not group then
      session.ui:append_error("model selection failed: selected provider disappeared from the conductor catalog")
      return
    end
    if #selectable_models(group) == 0 then
      authenticate_provider(session, group, true, function(authentication_error)
        if authentication_error then
          if authentication_error.code ~= "authentication_cancelled" then
            session.ui:append_error(format_error("authentication failed", authentication_error))
          end
          return
        end
        open_models(group)
      end)
      return
    end
    refresh_provider(session, group, function(refresh_error)
      if refresh_error then
        session.ui:append_error(format_error("model discovery failed", refresh_error))
        return
      end
      open_models(group)
    end)
  end

  session.controller.client:get_routing_catalog(function(result, routing_error)
    if routing_error then
      session.ui:append_error(format_error("routing discovery failed", routing_error))
      return
    end
    local profiles, catalog_error = routing_profiles(result)
    if catalog_error then
      session.ui:append_error(format_error("routing discovery failed", catalog_error))
      return
    end

    local providers = provider_groups(session.controller:state().catalogs)
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
          return routing_label(session, choice.value)
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
        session.ui:append_error("model selection failed: unknown target choice")
        return
      end
      authenticate_routing_profile(session, choice.value, function(authentication_error)
        if authentication_error then
          if authentication_error.code ~= "authentication_cancelled" then
            session.ui:append_error(format_error("routing authentication failed", authentication_error))
          end
          return
        end
        session.controller:set_target({ kind = "routed", value = choice.value.id }, function(_, error_value)
          if error_value then
            session.ui:append_error(format_error("failed to select routing profile", error_value))
            return
          end
          session:_sync_status()
        end)
      end)
    end)
  end)
  return true
end

function M.authenticate(session)
  if not session:is_ready() then
    vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
    return false
  end

  local providers = {}
  for _, provider in ipairs(provider_groups(session.controller:state().catalogs)) do
    if #provider.authentication_methods > 0 then
      providers[#providers + 1] = provider
    end
  end
  if #providers == 0 then
    vim.notify("Phenix: conductor exposes no selectable authentication methods", vim.log.levels.WARN)
    return false
  end

  vim.ui.select(providers, {
    prompt = "Authenticate provider",
    format_item = provider_label,
  }, function(provider)
    if not provider then
      return
    end
    authenticate_provider(session, provider, false, function(authentication_error)
      if authentication_error and authentication_error.code ~= "authentication_cancelled" then
        session.ui:append_error(format_error("authentication failed", authentication_error))
      end
    end)
  end)
  return true
end

return M
