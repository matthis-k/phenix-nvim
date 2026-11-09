local config = {
  refresh_interval = 300000,
}

local state = {
  remote = {},
  timer = nil,
}

local function status(buf)
  return vim.b[buf or 0].gitsigns_status_dict
end

-- Never spawn a synchronous Git process from a statusline render callback.
-- Pending and failed results are cached just like successful ones.
local function remote_for(value)
  if not value or not value.root or not value.head or value.head == "" then
    return nil
  end
  local cache_key = value.root .. "\0" .. value.head
  local cached = state.remote[cache_key]
  if cached then
    return cached
  end

  local result = { pending = true }
  state.remote[cache_key] = result
  local command = {
    "git", "-C", value.root, "rev-list", "--left-right", "--count", "HEAD...@{upstream}",
  }
  local ok, err = pcall(function()
    vim.system(command, { text = true }, function(process)
      vim.schedule(function()
        -- Ignore callbacks from an invalidated cache generation.
        if state.remote[cache_key] ~= result then
          return
        end
        result.pending = false
        if process.code ~= 0 then
          result.error = vim.trim(process.stderr or process.stdout or "")
          if result.error == "" then
            result.error = "remote unavailable"
          end
        else
          local ahead, behind = (process.stdout or ""):match("(%d+)%s+(%d+)")
          result.ahead = tonumber(ahead) or 0
          result.behind = tonumber(behind) or 0
        end
        vim.api.nvim_exec_autocmds("User", {
          pattern = "PhenixGitRemoteUpdate",
          data = { root = value.root, head = value.head },
        })
      end)
    end)
  end)
  if not ok then
    result.pending = false
    result.error = tostring(err)
  end
  return result
end

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
    vim.api.nvim_create_autocmd("VimLeavePre", {
      once = true,
      callback = function()
        state.timer:stop()
        state.timer:close()
        state.timer = nil
      end,
    })
  end
end

return api
