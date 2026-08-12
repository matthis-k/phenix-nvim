local M = {}

function M.lua_files(dir)
  local scanner = vim.uv.fs_scandir(dir)
  local result = {}
  if scanner then
    while true do
      local name = vim.uv.fs_scandir_next(scanner)
      if not name then
        break
      end
      local basename = name:match("^(.+)%.lua$")
      if basename then
        result[#result + 1] = { basename = basename, path = dir .. "/" .. name }
      end
    end
  end
  return result
end

function M.dirs(dir)
  local scanner = vim.uv.fs_scandir(dir)
  local result = {}
  if scanner then
    while true do
      local name, kind = vim.uv.fs_scandir_next(scanner)
      if not name then
        break
      end
      if kind == "directory" then
        result[#result + 1] = { basename = name, path = dir .. "/" .. name }
      end
    end
  end
  return result
end

M.highlights = setmetatable({}, {
  __index = function(_, key)
    return vim.api.nvim_get_hl(0, { name = key, link = false })
  end,
})

function M.utf8len(str)
  return #vim.str_utf_pos(str)
end

function M.utf8sub(str, start, stop)
  if stop < start then
    return ""
  end
  local positions = vim.str_utf_pos(str)
  if #positions < start then
    return ""
  end
  if #positions <= stop then
    return str:sub(positions[start])
  end
  return str:sub(positions[start], positions[stop + 1] - 1)
end

function M.validate(subject, schema, opts)
  local strict = opts == nil or opts.strict ~= false
  if strict then
    for key in pairs(subject) do
      if schema[key] == nil then
        return false
      end
    end
  end
  local valid = pcall(vim.validate, vim.iter(schema):map(function(key, value)
    return { subject[key], value }
  end):totable())
  return valid
end

local function foldlevel(line)
  return vim.fn.foldlevel(line)
end

---Return public-API fold information for one line in a window.
---This deliberately avoids Neovim's private C symbols so the config survives
---internal implementation changes across nightly builds.
---@param lnum integer
---@param win? integer
---@return table|nil
function M.foldexpr(lnum, win)
  local target = win or vim.api.nvim_get_current_win()
  if type(lnum) ~= "number" or not vim.api.nvim_win_is_valid(target) then
    return nil
  end

  return vim.api.nvim_win_call(target, function()
    local line_count = vim.api.nvim_buf_line_count(0)
    if lnum < 1 or lnum > line_count then
      return nil
    end

    local level = foldlevel(lnum)
    if level <= 0 then
      return { start = 0, ["end"] = 0, level = 0, lines = 0 }
    end

    local closed_start = vim.fn.foldclosed(lnum)
    if closed_start ~= -1 then
      local closed_end = vim.fn.foldclosedend(lnum)
      return {
        start = closed_start,
        ["end"] = closed_end,
        level = foldlevel(closed_start),
        lines = closed_end - closed_start + 1,
      }
    end

    local start_line = lnum
    while start_line > 1 and foldlevel(start_line - 1) >= level do
      start_line = start_line - 1
    end

    local end_line = lnum
    while end_line < line_count and foldlevel(end_line + 1) >= level do
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

local defined_highlights = {}
local highlight_fields = {
  "fg", "bg", "sp",
  "bold", "italic", "underline", "undercurl", "strikethrough", "reverse",
  "nocombine", "standout",
}

local function serialize_highlight(definition)
  local parts = {}
  for _, key in ipairs(highlight_fields) do
    local value = definition[key]
    if value == nil or value == false then
      parts[#parts + 1] = ""
    else
      parts[#parts + 1] = tostring(value):gsub("#", "")
    end
  end
  return "AutoHl" .. table.concat(parts, "IxI")
end

function M.auto_hl(definition)
  local key = serialize_highlight(definition)
  if not defined_highlights[key] then
    vim.api.nvim_set_hl(0, key, definition)
    defined_highlights[key] = true
  end
  return key
end

function M.to_hex(color)
  if type(color) ~= "number" then
    return nil
  end
  return string.format("#%06x", color)
end

return M
