local M = {}

local Group = {}
Group.__index = Group

local function valid_window(window)
  return window and vim.api.nvim_win_is_valid(window)
end

local function valid_buffer(buffer)
  return buffer and vim.api.nvim_buf_is_valid(buffer)
end

---Create a lifecycle scope for windows and buffers which together form one UI.
---A user closing any member tears down every member.  `unmount` is the explicit
---exception used for a temporary, non-destructive hide.
---@param opts? {on_close?: fun()}
---@return PhenixWindowGroup
function M.group(opts)
  opts = opts or {}
  local group = setmetatable({
    windows = {},
    buffers = {},
    closing = false,
    on_close = opts.on_close,
  }, Group)

  group.autocmd = vim.api.nvim_create_autocmd({ "WinClosed", "BufDelete", "BufWipeout" }, {
    callback = function(event)
      if group.closing then
        return
      end
      local member = event.event == "WinClosed" and tonumber(event.match) or event.buf
      local members = event.event == "WinClosed" and group.windows or group.buffers
      if members[member] then
        group:close()
      end
    end,
    desc = "Phenix UI group lifecycle",
  })
  return group
end

---@param window integer
function Group:add_window(window)
  self.windows[window] = true
  return window
end

---@param buffer integer
function Group:add_buffer(buffer)
  self.buffers[buffer] = true
  return buffer
end

---Remove a member before an intentional, partial layout transition.
function Group:remove_window(window)
  self.windows[window] = nil
end

---Intentionally close one window during a layout transition without treating it
---as a user-initiated group teardown.
function Group:detach_window(window)
  self:remove_window(window)
  if valid_window(window) then
    pcall(vim.api.nvim_win_close, window, true)
  end
end

function Group:remove_buffer(buffer)
  self.buffers[buffer] = nil
end

---Hide a group without destroying its buffers. User-initiated closes must use
---`close`, which is deliberately all-or-none.
function Group:unmount()
  if self.closing then
    return
  end
  self.closing = true
  for window in pairs(self.windows) do
    if valid_window(window) then
      pcall(vim.api.nvim_win_close, window, true)
    end
  end
  self.windows = {}
  self.closing = false
end

---Close every window and delete every buffer in this UI group.
function Group:close()
  if self.closing then
    return
  end
  self.closing = true
  for window in pairs(self.windows) do
    if valid_window(window) then
      pcall(vim.api.nvim_win_close, window, true)
    end
  end
  for buffer in pairs(self.buffers) do
    if valid_buffer(buffer) then
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
  end
  self.windows = {}
  self.buffers = {}
  self.closing = false
  if self.on_close then
    self.on_close()
  end
end

function Group:destroy()
  self:close()
  if self.autocmd then
    pcall(vim.api.nvim_del_autocmd, self.autocmd)
    self.autocmd = nil
  end
end

---Build content for a window-local status surface. Literal text is escaped so
---it cannot accidentally be interpreted as a Neovim statusline expression.
---@param part string|number|{text?: string|number, hl?: string, children?: table[]}|nil
---@return string
function M.line(part)
  local function text(value)
    return (tostring(value or ""):gsub("%%", "%%%%"))
  end
  local function render(value)
    if value == nil then
      return ""
    end
    if type(value) ~= "table" then
      return text(value)
    end
    local pieces = { text(value.text) }
    for _, child in ipairs(value.children or {}) do
      pieces[#pieces + 1] = render(child)
    end
    local content = table.concat(pieces)
    if content == "" or not value.hl or value.hl == "" then
      return content
    end
    return string.format("%%#%s#%s%%*", value.hl, content)
  end
  return render(part)
end

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
