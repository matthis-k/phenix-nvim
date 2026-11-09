local M = {}

function M.enable()
  vim.b.disable_autoformat = false
  vim.g.disable_autoformat = false
end

function M.disable(opts)
  if opts and opts.buffer then
    vim.b.disable_autoformat = true
  else
    vim.g.disable_autoformat = true
  end
end

function M.buffer()
  return require("conform").format({ async = true })
end

function M.range()
  return require("conform").format({
    async = true,
    range = {
      start = vim.api.nvim_buf_get_mark(0, "<"),
      ["end"] = vim.api.nvim_buf_get_mark(0, ">"),
    },
  })
end

return M
