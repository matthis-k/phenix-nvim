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
  for key, validator in pairs(schema) do
    if not pcall(vim.validate, key, subject[key], validator) then
      return false
    end
  end
  return true
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
