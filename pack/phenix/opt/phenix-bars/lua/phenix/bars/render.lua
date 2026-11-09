---@class PhenixBarsContext
---@field surface? string
---@field win? integer
---@field buf? integer
---@field memo? fun(key: string, compute: function): any

---@class PhenixBarsPart
---@field text? string|number|false|fun(ctx: PhenixBarsContext): string|number|false|nil
---@field raw? string|number|false|fun(ctx: PhenixBarsContext): string|number|false|nil
---@field hl? string|false|fun(ctx: PhenixBarsContext): string|false|nil
---@field before? PhenixBarsPartValue
---@field after? PhenixBarsPartValue
---@field children? PhenixBarsPart[]|fun(ctx: PhenixBarsContext): PhenixBarsPart[]
---@field child_sep? PhenixBarsPartValue
---@field enabled? boolean|fun(ctx: PhenixBarsContext): boolean
---@field on_click? string|fun(ctx: PhenixBarsContext): string|nil
---@field on_click_param? string|number|fun(ctx: PhenixBarsContext): string|number|nil
---@field render? fun(part: PhenixBarsPart, ctx: PhenixBarsContext): string

---@alias PhenixBarsPartValue string|number|false|PhenixBarsPart|fun(ctx: PhenixBarsContext): string|number|false|PhenixBarsPart|nil

local M = {}

local function resolve(value, ctx)
  if type(value) == "function" then
    return resolve(value(ctx), ctx)
  end
  return value
end

-- Unlike 'raw', text is literal and cannot inject statusline format items.
local function escape_text(value)
  if value == nil or value == false then
    return ""
  end
  return tostring(value):gsub("%%", "%%%%")
end

local function highlight_code(name)
  if name == nil or name == false or name == "" then
    return "%*"
  end
  if type(name) ~= "string" or not name:match("^[%w_@%.:%-]+$") then
    error("phenix.bars: invalid highlight group")
  end
  return "%#" .. name .. "#"
end

local function click_target(value)
  if value == nil or value == false or value == "" then
    return nil
  end
  if type(value) ~= "string" then
    error("phenix.bars: click target must be a string")
  end
  if value:match("^[%a_][%w_]*$") then
    return "v:lua.PhenixBars.click." .. value
  end
  if value:match("^v:lua%.[%w_%.]+$") then
    return value
  end
  error("phenix.bars: invalid click target")
end

local render_part

local function render_value(value, ctx, inherited_hl)
  value = resolve(value, ctx)
  if type(value) == "table" then
    return render_part(value, ctx, inherited_hl)
  end
  return escape_text(value)
end

render_part = function(part, ctx, inherited_hl)
  if part == nil or part == false then
    return ""
  end
  if type(part) ~= "table" then
    return render_value(part, ctx, inherited_hl)
  end
  if part.enabled ~= nil and not resolve(part.enabled, ctx) then
    return ""
  end
  if part.text ~= nil and part.raw ~= nil then
    error("phenix.bars: text and raw are mutually exclusive")
  end

  local requested_hl = resolve(part.hl, ctx)
  local active_hl = requested_hl and requested_hl ~= "" and requested_hl or inherited_hl
  local content
  if part.render ~= nil then
    -- A custom renderer produces trusted statusline syntax, but still participates
    -- in visibility, highlighting and click scoping.
    content = part.render(part, ctx) or ""
  else
    local children = resolve(part.children, ctx) or {}
    local rendered_children = {}
    for _, child in ipairs(children) do
      local rendered = render_part(child, ctx, active_hl)
      if rendered ~= "" then
        rendered_children[#rendered_children + 1] = rendered
      end
    end
    local separator = render_value(part.child_sep, ctx, active_hl)
    content = render_value(part.text, ctx, active_hl)
      .. (resolve(part.raw, ctx) == nil and "" or tostring(resolve(part.raw, ctx) or ""))
      .. table.concat(rendered_children, separator)
  end
  if content == "" then
    return ""
  end

  local body = render_value(part.before, ctx, active_hl)
    .. content
    .. render_value(part.after, ctx, active_hl)
  local target = click_target(resolve(part.on_click, ctx))
  if target then
    local param = resolve(part.on_click_param, ctx)
    if param ~= nil and param ~= false and tostring(param) ~= "" then
      param = tostring(param)
      if not param:match("^%d+$") then
        error("phenix.bars: click parameter must be a nonnegative integer")
      end
      body = "%" .. param .. "@" .. target .. "@" .. body .. "%T"
    else
      body = "%@" .. target .. "@" .. body .. "%T"
    end
  end

  if active_hl ~= inherited_hl then
    return highlight_code(active_hl) .. body .. highlight_code(inherited_hl)
  end
  return body
end

---@param part PhenixBarsPart|string|number|false|nil
---@param ctx? PhenixBarsContext
---@return string
function M.render(part, ctx)
  return render_part(part, ctx or {}, nil)
end

return M
