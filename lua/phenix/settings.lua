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
---@field chat_mode? boolean
---@field conductor_command? string|string[]
---@field conductor_socket? string
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
---@field chat_mode boolean
---@field conductor_command? string|string[]
---@field conductor_socket? string
---@field conductor_cwd_arg? boolean
---@field target? table
---@field session_id? string

local M = {}

---@type PhenixSettings
local built_in_defaults = {
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
  chat_mode = false,
}

---@type PhenixSettings
local configured = vim.deepcopy(built_in_defaults)

---@param options? PhenixOptions
---@return PhenixSettings
function M.merge(options)
  return vim.tbl_deep_extend("force", {}, configured, options or {})
end

---@param options? PhenixOptions
---@return PhenixSettings
function M.configure(options)
  configured = vim.tbl_deep_extend("force", {}, built_in_defaults, options or {})
  return M.current()
end

---@return PhenixSettings
function M.current()
  return vim.deepcopy(configured)
end

return M
