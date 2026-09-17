local M = {}

function M.focus_mouse_line(_minwid, _clicks, _button, _mods)
  local mouse = vim.fn.getmousepos()
  if mouse.winid > 0 and vim.api.nvim_win_is_valid(mouse.winid) then
    vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, 0 })
  end
end

function M.toggle_mouse_fold(_minwid, _clicks, _button, _mods)
  local mouse = vim.fn.getmousepos()
  if mouse.winid <= 0 or not vim.api.nvim_win_is_valid(mouse.winid) then
    return
  end

  local statuscolumn = require("phenix.bars.statuscolumn")
  local info = statuscolumn.fold_info(mouse.line, mouse.winid)
  if not info or info.start ~= mouse.line then
    return
  end

  vim.api.nvim_win_call(mouse.winid, function()
    if vim.fn.foldclosed(mouse.line) == -1 then
      vim.cmd(mouse.line .. "foldclose")
    else
      vim.cmd(mouse.line .. "foldopen")
    end
  end)
  statuscolumn.invalidate(mouse.winid)
end

function M.focus_buffer(minwid, _clicks, _button, _mods)
  local buf = tonumber(minwid)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local win = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(candidate)
    return vim.api.nvim_win_get_buf(candidate) == buf
  end)
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.api.nvim_set_current_buf(buf)
  end
end

function M.close_buffer(minwid, _clicks, _button, _mods)
  local buf = tonumber(minwid)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = false })
    vim.cmd.redrawtabline()
  end
end

function M.focus_tab(minwid, _clicks, _button, _mods)
  local tab = tonumber(minwid)
  if tab and vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
  end
end

function M.close_tab(minwid, _clicks, _button, _mods)
  local tab = tonumber(minwid)
  if not tab or not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end
  vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(tab))
  vim.cmd.redrawtabline()
end

return M
