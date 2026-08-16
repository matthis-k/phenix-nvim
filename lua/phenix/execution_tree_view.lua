local ExecutionTree = require("phenix.execution_tree")

local M = {}
local View = {}
View.__index = View

local function configure_buffer(buffer)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buffer })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buffer })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buffer })
  vim.api.nvim_set_option_value("filetype", "text", { buf = buffer })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buffer })
end

function M.new(ui)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buffer, "phenix://execution-tree/" .. tostring(buffer))
  configure_buffer(buffer)
  ui.window_group:add_buffer(buffer)
  return setmetatable({
    ui = assert(ui, "execution tree view requires the Phenix UI"),
    buffer = buffer,
    session_id = nil,
    rows = {},
  }, View)
end

function View:render(session_id, executions)
  self.session_id = session_id
  self.rows = ExecutionTree.project(session_id, executions)
  local lines = { "Execution tree", "" }
  vim.list_extend(lines, ExecutionTree.lines(session_id, executions))

  if not vim.api.nvim_buf_is_valid(self.buffer) then
    return
  end
  vim.api.nvim_set_option_value("modifiable", true, { buf = self.buffer })
  vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = self.buffer })
end

function View:is_visible()
  return self.ui.transcript_window ~= nil
    and vim.api.nvim_win_is_valid(self.ui.transcript_window)
    and vim.api.nvim_win_get_buf(self.ui.transcript_window) == self.buffer
end

function View:show()
  if not self.ui:is_visible() then
    return false
  end
  if not vim.api.nvim_buf_is_valid(self.buffer) then
    return false
  end
  return self.ui:show_transcript(self.buffer)
end

function View:hide()
  if not self.ui:is_visible() then
    return false
  end
  return self.ui:show_main_transcript()
end

function View:toggle()
  if self:is_visible() then
    return self:hide()
  end
  return self:show()
end

M.View = View
return M
