local M = {}

local Info = {}
Info.__index = Info

local function buffer(name)
  local value = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(value, name .. "/" .. tostring(value))
  vim.bo[value].buftype = "nofile"
  vim.bo[value].bufhidden = "hide"
  vim.bo[value].swapfile = false
  vim.bo[value].modifiable = false
  return value
end

local function set_lines(value, lines)
  vim.bo[value].modifiable = true
  vim.api.nvim_buf_set_lines(value, 0, -1, false, lines)
  vim.bo[value].modifiable = false
end

local function node_index(tree)
  local nodes = {}
  local children = {}
  for _, node in ipairs(tree.nodes or {}) do
    nodes[node.id] = node
    children[node.parent or false] = children[node.parent or false] or {}
    table.insert(children[node.parent or false], node)
  end
  for _, entries in pairs(children) do
    table.sort(entries, function(left, right)
      return left.id < right.id
    end)
  end
  return nodes, children
end

function M.new(options)
  options = options or {}
  local info = setmetatable({
    tree_buffer = buffer("phenix://workflow"),
    objectives_buffer = buffer("phenix://objectives"),
    files_buffer = buffer("phenix://edited-files"),
    windows = {},
    tree = nil,
    tree_lines = {},
    on_select_node = options.on_select_node,
  }, Info)

  vim.keymap.set("n", "<CR>", function()
    local node = info.tree_lines[vim.api.nvim_win_get_cursor(0)[1]]
    if node and info.on_select_node then
      info.on_select_node(node)
    end
  end, { buffer = info.tree_buffer, desc = "Phenix: show selected session transcript" })
  return info
end

function Info:is_visible()
  return #self.windows > 0 and vim.api.nvim_win_is_valid(self.windows[1])
end

function Info:hide()
  for _, window in ipairs(self.windows) do
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
  end
  self.windows = {}
end

function Info:toggle()
  if self:is_visible() then
    self:hide()
    return false
  end

  local width = math.min(math.max(math.floor(vim.o.columns * 0.3), 36), 56)
  local height = math.max(math.floor((vim.o.lines - 6) / 3), 4)
  local panels = {
    { buffer = self.tree_buffer, title = " Phenix workflow " },
    { buffer = self.objectives_buffer, title = " Phenix objectives " },
    { buffer = self.files_buffer, title = " Phenix edited files " },
  }
  for index, panel in ipairs(panels) do
    local window = vim.api.nvim_open_win(panel.buffer, index == 1, {
      relative = "editor",
      anchor = "NW",
      row = 1 + (index - 1) * (height + 1),
      col = 1,
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
      title = panel.title,
      title_pos = "center",
    })
    vim.wo[window].number = false
    vim.wo[window].relativenumber = false
    vim.wo[window].signcolumn = "no"
    vim.wo[window].wrap = false
    self.windows[index] = window
  end
  return true
end

function Info:set_tree(tree)
  self.tree = vim.deepcopy(tree)
  local nodes, children = node_index(self.tree)
  local lines = {}
  self.tree_lines = {}
  local function append(node, depth)
    local prefix = depth == 0 and "" or string.rep("  ", depth - 1) .. "└ "
    table.insert(lines, string.format("%s%s · %s · %s", prefix, node.role, node.state, node.id))
    self.tree_lines[#lines] = node.id
    for _, child in ipairs(children[node.id] or {}) do
      append(child, depth + 1)
    end
  end
  for _, node in ipairs(children[false] or {}) do
    append(node, 0)
  end
  set_lines(self.tree_buffer, #lines > 0 and lines or { "No workflow sessions." })

  local objectives = {}
  for _, objective in ipairs(self.tree.objectives or {}) do
    local workers = {}
    for _, node in pairs(nodes) do
      if node.objective_id == objective.id then
        table.insert(workers, node.role .. " (" .. node.state .. ")")
      end
    end
    table.sort(workers)
    table.insert(objectives, string.format("%s · %s", objective.state, objective.title))
    table.insert(objectives, "  " .. (#workers > 0 and table.concat(workers, ", ") or "No session assigned"))
  end
  set_lines(self.objectives_buffer, #objectives > 0 and objectives or { "No objectives." })
end

function Info:set_files(paths)
  local lines = {}
  for _, path in ipairs(paths or {}) do
    table.insert(lines, path)
  end
  set_lines(self.files_buffer, #lines > 0 and lines or { "No write-tool paths reported for this session subtree." })
end

M.Info = Info
return M
