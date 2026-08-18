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
    if type(profile) ~= "string" or vim.trim(profile) == "" then
      return nil, "routing catalog contains an invalid profile id"
    end
    if not seen[profile] then
      seen[profile] = true
      profiles[#profiles + 1] = profile
    end
  end
  table.sort(profiles)
  return profiles
end

local function choose_route(session, profile)
  session.controller:set_target({ kind = "routed", value = profile }, function(_, error_value)
    if error_value then
      session.ui:append_error(error_message("failed to select routing", error_value))
    end
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
          return "routing · " .. choice.profile
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
  function Session:select_model()
    if not self:is_ready() then
      return direct_select(self)
    end

    self.controller.client:get_routing_catalog(function(result, error_value)
      if error_value then
        self.ui:append_error(error_message("routing discovery failed", error_value))
        return
      end
      local profiles, validation_error = routing_profiles(result)
      if validation_error then
        self.ui:append_error("routing discovery failed: " .. validation_error)
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
end

return M
