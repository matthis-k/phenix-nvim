local M = {}

---@param buffer integer
---@param window integer
function M.prepare_window(buffer, window)
  if not vim.api.nvim_buf_is_valid(buffer) or vim.api.nvim_win_get_buf(window) ~= buffer then
    return
  end
  if not vim.api.nvim_buf_get_name(buffer):match("^phenix://transcript/") then
    return
  end

  local ok, markview = pcall(require, "markview")
  if not ok then
    return
  end

  vim.api.nvim_set_option_value("conceallevel", 3, { win = window })
  vim.api.nvim_set_option_value("concealcursor", "nc", { win = window })
  if markview.actions and type(markview.actions.set_query) == "function" then
    pcall(markview.actions.set_query, buffer)
  end
end

return M
