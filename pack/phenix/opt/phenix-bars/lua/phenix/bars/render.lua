---@class PhenixBarsPart
---@field text? string|number|false|fun(): string|number|false|nil
---@field hl? string|false|fun(): string|false|nil
---@field before? PhenixBarsPartValue
---@field after? PhenixBarsPartValue
---@field children? PhenixBarsPart[]|fun(): PhenixBarsPart[]
---@field child_sep? PhenixBarsPartValue
---@field enabled? boolean|fun(): boolean
---@field on_click? string|fun(): string|nil
---@field on_click_param? string|number|fun(): string|number|nil
---@field render? fun(part: PhenixBarsPart): string

---@alias PhenixBarsPartValue string|number|false|PhenixBarsPart|fun(): string|number|false|PhenixBarsPart|nil

local M = {}

---@param value any
---@return string
local function evaluate(value)
  if value == nil or value == false then
    return ""
  end
  if type(value) == "string" or type(value) == "number" then
    return tostring(value)
  end
  if type(value) == "function" then
    return evaluate(value())
  end
  if type(value) == "table" then
    return M.render(value)
  end
  return tostring(value)
end

---@param target string
---@return string
local function click_target(target)
  if target == "" or target:match("^v:lua%.") then
    return target
  end
  return "v:lua.PhenixBars.click." .. target
end

---@param part PhenixBarsPart|string|number|false|nil
---@return string
function M.render(part)
  if part == nil or part == false then
    return ""
  end
  if type(part) ~= "table" then
    return evaluate(part)
  end
  if type(part.render) == "function" then
    return part.render(part)
  end
  if part.enabled ~= nil then
    local enabled = type(part.enabled) == "function" and part.enabled() or part.enabled
    if not enabled then
      return ""
    end
  end

  local hl = evaluate(part.hl)
  local highlighted = hl ~= "" and string.format("%%#%s#", hl) or ""
  local children = type(part.children) == "function" and part.children() or (part.children or {})
  local rendered_children = {}
  for _, child in ipairs(children) do
    local rendered = M.render(child)
    if rendered ~= "" then
      rendered_children[#rendered_children + 1] = rendered .. highlighted
    end
  end

  local content = evaluate(part.text) .. table.concat(rendered_children, evaluate(part.child_sep))
  if content == "" then
    return ""
  end

  local before = evaluate(part.before)
  local after = evaluate(part.after)
  local target = click_target(evaluate(part.on_click))
  if target == "" then
    return highlighted .. before .. content .. after
  end

  local parameter = evaluate(part.on_click_param)
  local prefix = parameter ~= "" and string.format("%%%s@%s@", parameter, target) or string.format("%%@%s@", target)
  return prefix .. highlighted .. before .. content .. after .. "%T"
end

return M
