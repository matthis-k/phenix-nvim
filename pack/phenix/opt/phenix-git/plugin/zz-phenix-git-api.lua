local Frontend = require("phenix.frontend")
local config = Frontend.config("git", {
  refresh_interval = 300000,
})

local state = {
  remote = {},
  timer = nil,
}

local function status(buf)
  return vim.b[buf or 0].gitsigns_status_dict
end

local function remote_for(value)
  if not value or not value.root or not value.head or value.head == "" then
    return nil
  end
  local cached = state.remote[value.root]
  if cached then
    return cached
  end

  local result = { ahead = 0, behind = 0 }
  local output = vim.fn.system({
    "git",
    "-C",
    value.root,
    "rev-list",
    "--left-right",
    "--count",
    value.head .. "..origin/" .. value.head,
  })
  if vim.v.shell_error ~= 0 then
    result.error = vim.trim(output) ~= "" and vim.trim(output) or "remote unavailable"
  else
    local ahead, behind = output:match("(%d+)%s+(%d+)")
    result.ahead = tonumber(ahead) or 0
    result.behind = tonumber(behind) or 0
  end
  state.remote[value.root] = result
  return result
end

---@type PhenixGit
local api = {}

api.status = status

function api.remote(buf)
  return remote_for(status(buf))
end

function api.refresh()
  state.remote = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      remote_for(status(buf))
    end
  end
end

function api.is_sign_namespace(namespace)
  return type(namespace) == "string" and namespace:match("^gitsigns_signs") ~= nil
end

if config.refresh_interval > 0 then
  state.timer = vim.uv.new_timer()
  if state.timer then
    state.timer:start(config.refresh_interval, config.refresh_interval, vim.schedule_wrap(api.refresh))
  end
end

Frontend.register_api("git", api, {
  contract = {
    status = "function",
    remote = "function",
    refresh = "function",
    is_sign_namespace = "function",
  },
  state = state,
})
