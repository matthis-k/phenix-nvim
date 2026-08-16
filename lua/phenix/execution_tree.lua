local M = {}

local function execution_number(id)
  return tonumber(tostring(id or ""):match("(%d+)$"))
end

local function compare_execution(left, right)
  local left_number = execution_number(left.id)
  local right_number = execution_number(right.id)
  if left_number and right_number and left_number ~= right_number then
    return left_number < right_number
  end
  return tostring(left.id) < tostring(right.id)
end

local function target_label(target)
  if type(target) ~= "table" then
    return ""
  end
  if target.kind == "routed" then
    return "routing/" .. tostring(target.value or "")
  end
  if target.kind ~= "fixed" or type(target.value) ~= "table" then
    return ""
  end
  local value = target.value
  local parts = {}
  for _, field in ipairs({ "backend", "provider", "model" }) do
    if value[field] and value[field] ~= "" then
      parts[#parts + 1] = tostring(value[field])
    end
  end
  return table.concat(parts, "/")
end

local function execution_label(execution)
  local subject = execution.callable or execution.kind or execution.id or "execution"
  local state = execution.state or "unknown"
  local target = target_label(execution.target)
  local label = string.format("[%s] %s", tostring(state), tostring(subject))
  if target ~= "" then
    label = label .. " · " .. target
  end
  return label
end

function M.project(session_id, executions)
  local by_id = {}
  for _, execution in pairs(executions or {}) do
    if type(execution) == "table" and execution.id and (session_id == nil or execution.session_id == session_id) then
      by_id[execution.id] = vim.deepcopy(execution)
    end
  end

  local children = {}
  local roots = {}
  for id, execution in pairs(by_id) do
    local parent = execution.parent_execution
    if parent and by_id[parent] then
      children[parent] = children[parent] or {}
      children[parent][#children[parent] + 1] = execution
    else
      roots[#roots + 1] = execution
    end
    children[id] = children[id] or {}
  end
  table.sort(roots, compare_execution)
  for _, values in pairs(children) do
    table.sort(values, compare_execution)
  end

  local rows = {}
  local visited = {}
  local function visit(execution, depth)
    if visited[execution.id] then
      return
    end
    visited[execution.id] = true
    rows[#rows + 1] = {
      id = execution.id,
      parent_execution = execution.parent_execution,
      depth = depth,
      kind = execution.kind,
      callable = execution.callable,
      state = execution.state,
      target = vim.deepcopy(execution.target),
      label = execution_label(execution),
      has_children = #children[execution.id] > 0,
    }
    for _, child in ipairs(children[execution.id]) do
      visit(child, depth + 1)
    end
  end

  for _, execution in ipairs(roots) do
    visit(execution, 0)
  end

  -- Corrupt or cyclic parent references must not make executions disappear
  -- from the local view. The conductor remains authoritative; the frontend
  -- simply renders any unvisited execution as an additional root.
  local remainder = {}
  for id, execution in pairs(by_id) do
    if not visited[id] then
      remainder[#remainder + 1] = execution
    end
  end
  table.sort(remainder, compare_execution)
  for _, execution in ipairs(remainder) do
    visit(execution, 0)
  end

  return rows
end

function M.lines(session_id, executions)
  local rows = M.project(session_id, executions)
  if #rows == 0 then
    return { "No executions" }
  end

  local lines = {}
  for _, row in ipairs(rows) do
    lines[#lines + 1] = string.rep("  ", row.depth) .. "• " .. row.label
  end
  return lines
end

return M
