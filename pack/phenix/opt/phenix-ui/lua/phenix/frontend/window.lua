local M = {}

---@param window integer
---@param options table<string, any>
function M.set_options(window, options)
  for name, value in pairs(options) do
    vim.api.nvim_set_option_value(name, value, { win = window })
  end
end

---@param window integer
function M.configure_text(window)
  M.set_options(window, {
    number = false,
    relativenumber = false,
    statuscolumn = "",
    wrap = true,
    linebreak = true,
  })
end

---@param name string
---@param opts? table
---@return integer, integer
function M.scratch(name, opts)
  opts = opts or {}
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buffer, name)
  local window = vim.api.nvim_open_win(buffer, opts.enter == true, vim.tbl_extend("force", {
    relative = "editor",
    width = math.max(1, math.floor(vim.o.columns * 0.5)),
    height = math.max(1, math.floor(vim.o.lines * 0.5)),
    row = 1,
    col = 1,
    style = "minimal",
    border = "rounded",
  }, opts.window or {}))
  return buffer, window
end

return M
