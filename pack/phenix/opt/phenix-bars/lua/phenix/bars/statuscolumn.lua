local M = {}

---@class PhenixBarsSignColumnConfig
---@field width integer
---@field filter? fun(namespace: string, mark: table): boolean

---@type table<string, PhenixBarsSignColumnConfig>
local columns = {}
local cache = {}

local function normalize_window(win)
  return type(win) == "string" and tonumber(win) or win
end

local function supported_window(win)
  return type(win) == "number"
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_config(win).relative == ""
end

local function default_fold_info(lnum, win)
  local target = normalize_window(win) or vim.api.nvim_get_current_win()
  if type(lnum) ~= "number" or not supported_window(target) then
    return nil
  end

  return vim.api.nvim_win_call(target, function()
    local line_count = vim.api.nvim_buf_line_count(0)
    if lnum < 1 or lnum > line_count then
      return nil
    end

    local level = vim.fn.foldlevel(lnum)
    if level <= 0 then
      return { start = 0, ["end"] = 0, level = 0, lines = 0 }
    end

    local closed_start = vim.fn.foldclosed(lnum)
    if closed_start ~= -1 then
      local closed_end = vim.fn.foldclosedend(lnum)
      return {
        start = closed_start,
        ["end"] = closed_end,
        level = vim.fn.foldlevel(closed_start),
        lines = closed_end - closed_start + 1,
      }
    end

    local start_line = lnum
    while start_line > 1 and vim.fn.foldlevel(start_line - 1) >= level do
      start_line = start_line - 1
    end

    local end_line = lnum
    while end_line < line_count and vim.fn.foldlevel(end_line + 1) >= level do
      end_line = end_line + 1
    end

    return {
      start = start_line,
      ["end"] = end_line,
      level = level,
      lines = 0,
    }
  end)
end

local fold_info_provider = default_fold_info

---@param provider fun(lnum: integer, win?: integer): table|nil
function M.configure_fold_provider(provider)
  vim.validate("provider", provider, "function")
  fold_info_provider = provider
end

---@param lnum integer
---@param win? integer|string
---@return table|nil
function M.fold_info(lnum, win)
  return fold_info_provider(lnum, normalize_window(win))
end

local function assign_sign_columns(snapshot)
  snapshot.sign_columns = {}
  for name, definition in pairs(columns) do
    local assigned = {}
    local empty = true
    for lnum = snapshot.first_line, snapshot.last_line do
      local best = nil
      for _, mark in ipairs(snapshot.lines[lnum] or {}) do
        local namespace = snapshot.namespaces[mark.details.ns_id] or ""
        if (not definition.filter or definition.filter(namespace, mark)) and mark.details.sign_text then
          local priority = mark.details.priority or 0
          local best_priority = best and (best.details.priority or 0) or -1
          if not best
            or priority > best_priority
            or (priority == best_priority and mark.details.ns_id < best.details.ns_id)
          then
            best = mark
          end
        end
      end
      assigned[lnum] = best
      empty = empty and best == nil
    end
    snapshot.sign_columns[name] = {
      assigned = assigned,
      empty = empty,
      width = definition.width,
    }
  end
end

local function snapshot_window(win)
  if not supported_window(win) then
    cache[win] = nil
    return nil
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local snapshot = {
    win = win,
    buf = buf,
    lines = {},
    first_line = vim.fn.line("w0", win),
    last_line = vim.fn.line("w$", win),
    namespaces = {},
    cursor_line = nil,
    current_fold = nil,
  }

  local wo = vim.wo[win]
  if wo.relativenumber and not wo.number then
    snapshot.numberwidth = math.max(3, wo.numberwidth)
  elseif wo.number then
    snapshot.numberwidth = math.max(wo.numberwidth, #tostring(vim.api.nvim_buf_line_count(buf)) + 1)
  else
    snapshot.numberwidth = 0
  end

  for namespace, id in pairs(vim.api.nvim_get_namespaces()) do
    snapshot.namespaces[id] = namespace
  end

  local marks = vim.api.nvim_buf_get_extmarks(
    buf,
    -1,
    { snapshot.first_line - 1, 0 },
    { snapshot.last_line - 1, -1 },
    { details = true, type = "sign" }
  )
  for _, mark in ipairs(marks) do
    local lnum = mark[2] + 1
    snapshot.lines[lnum] = snapshot.lines[lnum] or {}
    snapshot.lines[lnum][#snapshot.lines[lnum] + 1] = {
      id = mark[1],
      row = mark[2],
      col = mark[3],
      details = mark[4],
    }
  end

  assign_sign_columns(snapshot)
  cache[win] = snapshot
  return snapshot
end

local function update_cursor_fold(snapshot)
  local cursor_line = vim.api.nvim_win_get_cursor(snapshot.win)[1]
  if snapshot.cursor_line == cursor_line then
    return
  end
  snapshot.cursor_line = cursor_line
  local current = M.fold_info(cursor_line, snapshot.win)
  snapshot.current_fold = current and current.level > 0 and current or nil
end

---@param name string
---@param definition PhenixBarsSignColumnConfig
function M.configure_sign_column(name, definition)
  vim.validate("name", name, "string")
  vim.validate("definition", definition, "table")
  vim.validate("definition.width", definition.width, "number")
  if definition.filter ~= nil then
    vim.validate("definition.filter", definition.filter, "function")
  end
  columns[name] = {
    width = math.max(0, math.floor(definition.width)),
    filter = definition.filter,
  }
  M.invalidate()
end

---@param name string
function M.remove_sign_column(name)
  columns[name] = nil
  M.invalidate()
end

---@param win? integer|string
function M.invalidate(win)
  win = normalize_window(win)
  if win then
    cache[win] = nil
  else
    cache = {}
  end
end

---@param win? integer|string
function M.refresh(win)
  win = normalize_window(win)
  if win then
    snapshot_window(win)
    return
  end
  cache = {}
  for _, candidate in ipairs(vim.api.nvim_list_wins()) do
    if supported_window(candidate) then
      snapshot_window(candidate)
    end
  end
end

---@param win integer|string
---@return table|nil
function M.get(win)
  win = normalize_window(win)
  if not supported_window(win) then
    return nil
  end
  local snapshot = cache[win] or snapshot_window(win)
  if snapshot then
    update_cursor_fold(snapshot)
  end
  return snapshot
end

---@param name string
---@param opts? table
---@return PhenixBarsPart
function M.sign_part(name, opts)
  opts = opts or {}
  return {
    name = name,
    enabled = function()
      local snapshot = M.get(vim.g.statusline_winid)
      local column = snapshot and snapshot.sign_columns[name]
      return not (opts.auto_hide and column and column.empty)
    end,
    text = function()
      local snapshot = M.get(vim.g.statusline_winid)
      local column = snapshot and snapshot.sign_columns[name]
      if not column then
        return ""
      end
      local mark = column.assigned[vim.v.lnum]
      if not mark then
        return string.rep(" ", column.width)
      end
      return vim.fn.strcharpart(mark.details.sign_text, 0, column.width)
    end,
    hl = function()
      local snapshot = M.get(vim.g.statusline_winid)
      local column = snapshot and snapshot.sign_columns[name]
      local mark = column and column.assigned[vim.v.lnum]
      return mark and mark.details.sign_hl_group or opts.hl or ""
    end,
  }
end

---@param opts? table
---@return PhenixBarsPart
function M.number_part(opts)
  opts = opts or {}
  return {
    name = opts.name or "number",
    on_click = opts.on_click,
    text = function()
      local win = normalize_window(vim.g.statusline_winid)
      local snapshot = M.get(win)
      local width = snapshot and snapshot.numberwidth or 0
      if vim.v.virtnum ~= 0 or width == 0 then
        return string.rep(" ", width)
      end
      local wo = vim.wo[win]
      local number = nil
      if wo.number and wo.relativenumber then
        number = vim.v.relnum == 0 and vim.v.lnum or vim.v.relnum
      elseif wo.number then
        number = vim.v.lnum
      elseif wo.relativenumber then
        number = vim.v.relnum
      end
      if number == nil then
        return string.rep(" ", width)
      end
      local flag = vim.v.relnum == 0 and "-" or ""
      return string.format("%" .. flag .. width .. "d", number)
    end,
    hl = function()
      local win = normalize_window(vim.g.statusline_winid)
      if supported_window(win) and vim.v.relnum == 0 and vim.wo[win].relativenumber then
        return opts.current_hl or opts.hl or ""
      end
      return opts.hl or ""
    end,
  }
end

---@param opts? table
---@return PhenixBarsPart
function M.fold_part(opts)
  opts = opts or {}
  return {
    name = opts.name or "fold",
    on_click = opts.on_click,
    text = function()
      local fillchars = vim.opt.fillchars:get()
      local info = M.fold_info(vim.v.lnum, vim.g.statusline_winid)
      if not info or info.level < 1 then
        return " "
      end
      if info.start ~= vim.v.lnum then
        return fillchars.foldsep or " "
      end
      return info.lines > 0 and (fillchars.foldclose or "+") or (fillchars.foldopen or "-")
    end,
    hl = function()
      local snapshot = M.get(vim.g.statusline_winid)
      local current = snapshot and snapshot.current_fold
      if current and vim.v.lnum >= current.start and vim.v.lnum <= current["end"] then
        return opts.current_hl or opts.hl or ""
      end
      return opts.hl or ""
    end,
  }
end

return M
