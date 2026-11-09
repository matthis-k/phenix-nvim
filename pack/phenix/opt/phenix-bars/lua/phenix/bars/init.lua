local Renderer = require("phenix.bars.render")

---@alias PhenixBarsSurface PhenixBarsPart|fun(ctx: PhenixBarsContext): PhenixBarsPart|string|false

---@class PhenixBarsConfig
---@field statusline? PhenixBarsSurface
---@field tabline? PhenixBarsSurface
---@field statuscolumn? PhenixBarsSurface

local M = {}

---@type table<string, PhenixBarsSurface>
local surfaces = {
  statusline = {
    children = {
      { before = " ", raw = "%f" },
      { before = " ", raw = "%m" },
      { raw = "%=" },
      { after = " ", raw = "%l:%c" },
    },
  },
  tabline = { before = " ", raw = "%f" },
  statuscolumn = { raw = "%s%C%=%l " },
}

local valid_surfaces = {
  statusline = true,
  tabline = true,
  statuscolumn = true,
}

---@param options? PhenixBarsConfig
---@return table<string, PhenixBarsSurface>
function M.configure(options)
  for surface, spec in pairs(options or {}) do
    if not valid_surfaces[surface] then
      error("phenix.bars: unknown surface " .. tostring(surface))
    end
    surfaces[surface] = spec
  end
  return M.current()
end

---@return table<string, PhenixBarsSurface>
function M.current()
  return vim.deepcopy(surfaces)
end

---@param surface string
---@return string
function M.render(surface)
  if not valid_surfaces[surface] then
    return ""
  end
  local win = tonumber(vim.g.statusline_winid)
  if not win or not vim.api.nvim_win_is_valid(win) then
    win = vim.api.nvim_get_current_win()
  end
  local values = {}
  local ctx = {
    surface = surface,
    win = win,
    buf = vim.api.nvim_win_get_buf(win),
    memo = function(key, compute)
      local entry = values[key]
      if not entry then
        entry = { value = compute() }
        values[key] = entry
      end
      return entry.value
    end,
  }
  local spec = surfaces[surface]
  if type(spec) == "function" then
    spec = spec(ctx)
  end
  return Renderer.render(spec, ctx)
end

---@param name string
---@param callback function
function M.register_click(name, callback)
  vim.validate("name", name, "string")
  vim.validate("callback", callback, "function")
  if not name:match("^[%a_][%w_]*$") then
    error("phenix.bars: click handler names must be Lua identifiers")
  end
  _G.PhenixBars = _G.PhenixBars or {}
  _G.PhenixBars.click = _G.PhenixBars.click or {}
  _G.PhenixBars.click[name] = callback
end

---@param part PhenixBarsPart|string|number|false|nil
---@param ctx? PhenixBarsContext
---@return string
function M.render_part(part, ctx)
  return Renderer.render(part, ctx)
end

return M
