-- Compact, event-driven LSP work-done progress for the distribution statusline.
-- This module owns presentation state; it never consumes client.progress rings.
local M = {}

local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local active = {} ---@type table<integer, { name: string, tokens: table<string, table> }>
local frame_index = 1
local timer

local function redraw()
  vim.cmd.redrawstatus()
end

local function token_key(token)
  return type(token) .. ":" .. tostring(token)
end

local function has_active()
  return next(active) ~= nil
end

local function stop_timer()
  if timer and not timer:is_closing() then
    timer:stop()
  end
end

local function tick()
  -- A stopped client may not emit an explicit 'end' for its work tokens.
  for id in pairs(active) do
    if not vim.lsp.get_client_by_id(id) then
      active[id] = nil
    end
  end
  if not has_active() then
    stop_timer()
    redraw()
    return
  end
  frame_index = frame_index % #frames + 1
  redraw()
end

local function start_timer()
  if not timer then
    timer = assert(vim.uv.new_timer(), "could not create LSP progress timer")
  end
  if not timer:is_active() then
    timer:start(0, 120, vim.schedule_wrap(tick))
  end
end

---@param client_id integer
---@param token string|integer
---@param value table
---@param name? string
function M.update(client_id, token, value, name)
  if type(client_id) ~= "number" or token == nil or type(value) ~= "table" then
    return
  end
  if value.kind ~= "begin" and value.kind ~= "report" and value.kind ~= "end" then
    return
  end

  local key = token_key(token)
  local client = active[client_id]
  if value.kind == "end" then
    if client then
      client.tokens[key] = nil
      if not next(client.tokens) then
        active[client_id] = nil
      end
    end
  else
    if not client then
      client = { name = name or "LSP", tokens = {} }
      active[client_id] = client
    end
    if name then
      client.name = name
    end
    local previous = client.tokens[key]
    local percentage = type(value.percentage) == "number"
      and math.max(0, math.min(100, value.percentage))
      or (previous and previous.percentage)
    client.tokens[key] = { percentage = percentage }
  end

  if has_active() then
    start_timer()
  else
    stop_timer()
  end
  redraw()
end

---@param ev table
function M.handle(ev)
  local data = ev and ev.data
  local params = data and data.params
  if not params then
    return
  end
  local client = vim.lsp.get_client_by_id(data.client_id)
  if not client then
    return
  end
  M.update(data.client_id, params.token, params.value, client.name)
end

--- Snapshot is deterministic for a given event stream and does not consume
--- Neovim's progress ring buffer (which other UI consumers may also inspect).
function M.current()
  local names = {}
  local percents = {}
  local all_known = true
  for _, client in pairs(active) do
    names[#names + 1] = client.name
    for _, value in pairs(client.tokens) do
      if value.percentage == nil then
        all_known = false
      else
        percents[#percents + 1] = value.percentage
      end
    end
  end
  table.sort(names)
  if #names == 0 then
    return nil
  end
  local percentage
  if all_known and #percents > 0 then
    local total = 0
    for _, value in ipairs(percents) do
      total = total + value
    end
    percentage = math.floor(total / #percents + 0.5)
  end
  return { spinner = frames[frame_index], count = #names, name = names[1], percentage = percentage }
end

local function snapshot(ctx)
  if ctx and ctx.memo then
    return ctx.memo("lsp_progress", M.current)
  end
  return M.current()
end

M.part = {
  enabled = function(ctx)
    return snapshot(ctx) ~= nil
  end,
  child_sep = " ",
  children = function(ctx)
    local data = snapshot(ctx)
    if not data then
      return {}
    end
    local elements = {
      { text = data.spinner, hl = "StlLspSpinner" },
    }
    if data.count == 1 then
      if data.percentage then
        elements[#elements + 1] = { text = data.percentage .. "%", hl = "StlLspProgress" }
      end
      elements[#elements + 1] = { text = data.name, hl = "StlLspName" }
    else
      elements[#elements + 1] = {
        text = string.format("%d LSPs loading", data.count),
        hl = "StlLspName",
      }
      if data.percentage then
        elements[#elements + 1] = { text = data.percentage .. "%", hl = "StlLspProgress" }
      end
    end
    return elements
  end,
}

function M.setup()
  local group = vim.api.nvim_create_augroup("PhenixLspProgress", { clear = true })
  vim.api.nvim_create_autocmd("LspProgress", {
    group = group,
    callback = M.handle,
    desc = "Update compact LSP statusline progress",
  })
  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(ev)
      local id = ev.data and ev.data.client_id
      if not id then
        return
      end
      -- A client may be detached from one buffer but remain attached to
      -- another; prune only after the client has actually terminated.
      vim.schedule(function()
        if not vim.lsp.get_client_by_id(id) then
          active[id] = nil
          if not has_active() then
            stop_timer()
          end
          redraw()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    once = true,
    callback = function()
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
      timer = nil
    end,
  })
end

-- Also useful to reset preview state in integration tests.
function M.clear()
  active = {}
  stop_timer()
  frame_index = 1
  redraw()
end

return M
