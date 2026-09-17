---@class PhenixColorPreviewConfig
---@field border? string|string[]
---@field palette? fun(): table<string, string|integer>

local M = {}
local window = nil
local buffer = nil

local function highlight_palette()
  local groups = {
    "Normal",
    "Comment",
    "String",
    "Function",
    "Type",
    "DiagnosticError",
    "DiagnosticWarn",
    "DiagnosticInfo",
    "DiagnosticHint",
  }
  local palette = {}
  for _, group in ipairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
    if hl.fg then
      palette[group] = hl.fg
    end
  end
  return palette
end

local config = {
  border = "rounded",
  palette = highlight_palette,
}

---@param options? PhenixColorPreviewConfig
---@return PhenixColorPreviewConfig
function M.configure(options)
  config = vim.tbl_extend("force", {}, config, options or {})
  return vim.deepcopy(config)
end

---@return boolean
function M.is_open()
  return window ~= nil and vim.api.nvim_win_is_valid(window)
end

function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(window, true)
  end
  window = nil
  buffer = nil
end

function M.toggle()
  if M.is_open() then
    M.close()
    return
  end

  local palette = config.palette()
  local keys = vim.tbl_keys(palette)
  table.sort(keys)
  if #keys == 0 then
    vim.notify("Phenix color preview: palette is empty", vim.log.levels.WARN)
    return
  end

  buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_name(buffer, "phenix://color-preview")

  local swatch = "███"
  local lines = {}
  local width = 1
  for _, key in ipairs(keys) do
    local line = string.format("%s: %s", key, swatch)
    lines[#lines + 1] = line
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false

  window = vim.api.nvim_open_win(buffer, false, {
    relative = "editor",
    width = width,
    height = #lines,
    row = 1,
    col = math.max(0, vim.o.columns - width - 2),
    style = "minimal",
    border = config.border,
  })

  local namespace = vim.api.nvim_create_namespace("phenix-color-preview")
  for index, key in ipairs(keys) do
    local group = "PhenixColorPreview" .. index
    vim.api.nvim_set_hl(0, group, { fg = palette[key] })
    local start_col = #key + 2
    vim.api.nvim_buf_set_extmark(buffer, namespace, index - 1, start_col, {
      end_col = start_col + #swatch,
      hl_group = group,
    })
  end
end

return M
