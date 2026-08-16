---@class PhenixOptions
---@field width? number
---@field input_height? number
---@field input_height_min? number
---@field input_height_max? number
---@field image_height? number
---@field image_width? number
---@field image_paste_command? string[]
---@field follow_up_height? number
---@field follow_up_height_min? number
---@field follow_up_height_max? number
---@field fullscreen? boolean
---@field tab? boolean
---@field conductor_command? string|string[]
---@field conductor_cwd_arg? boolean
---@field target? table
---@field session_id? string

---@class PhenixSettings
---@field width number
---@field input_height number
---@field input_height_min number
---@field input_height_max number
---@field image_height number
---@field image_width number
---@field image_paste_command? string[]
---@field follow_up_height number
---@field follow_up_height_min number
---@field follow_up_height_max number
---@field fullscreen boolean
---@field tab boolean
---@field conductor_command? string|string[]
---@field conductor_cwd_arg? boolean
---@field target? table
---@field session_id? string

local M = {}

---@type PhenixSettings
local defaults = {
  width = 0.5,
  input_height = 0.33,
  input_height_min = 6,
  input_height_max = 20,
  image_height = 5,
  image_width = 40,
  follow_up_height = 0.25,
  follow_up_height_min = 4,
  follow_up_height_max = 12,
  fullscreen = false,
  tab = false,
}

---@param options? PhenixOptions
---@return PhenixSettings
function M.merge(options)
  return vim.tbl_deep_extend("force", {}, defaults, options or {})
end

---@param options? PhenixOptions
---@return PhenixSettings
function M.configure(options)
  defaults = M.merge(options)
  return M.current()
end

---@return PhenixSettings
function M.current()
  return vim.deepcopy(defaults)
end

return M
