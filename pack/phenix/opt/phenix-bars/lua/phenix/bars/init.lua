local Renderer = require("phenix.bars.render")

---@alias PhenixBarsSurface PhenixBarsPart|fun(): PhenixBarsPart|string|false

---@class PhenixBarsConfig
---@field statusline? PhenixBarsSurface
---@field tabline? PhenixBarsSurface
---@field statuscolumn? PhenixBarsSurface

local M = {}

---@type table<string, PhenixBarsSurface>
local surfaces = {
  statusline = {
    children = {
      { before = " ", text = "%f" },
      { before = " ", text = "%m" },
      { text = "%=" },
      { after = " ", text = "%l:%c" },
    },
  },
  tabline = { before = " ", text = "%f" },
  statuscolumn = { text = "%s%C%=%l " },
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
  local spec = surfaces[surface]
  if type(spec) == "function" then
    spec = spec()
  end
  return Renderer.render(spec)
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
---@return string
function M.render_part(part)
  return Renderer.render(part)
end

return M
