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

return M
