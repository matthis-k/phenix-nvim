local M = {}
local Renderer = {}
Renderer.__index = Renderer

local function clear_ui_projection(ui)
  -- Clear entries for the current active session only
  local session_id = ui:_current_session_id()
  ui.entries_by_session[session_id] = {}
  ui.tool_entries_by_session[session_id] = {}
  ui.fold_ranges_by_session[session_id] = {}
  ui.fold_previews_by_session[session_id] = {}
  if rawget(ui, "_entries_by_id_cache") then
    ui._entries_by_id_cache[session_id] = setmetatable({}, { __mode = "v" })
  end
  ui.active_stream = nil
  ui.startup_banner_pending = false
  ui.startup_banner = ""
end

local function update_entry(ui, id, kind, fields)
  local entry = ui.entries_by_id[id]
  if not entry then
    fields = vim.deepcopy(fields)
    fields.id = id
    fields.kind = kind
    return ui:_append_entry(fields)
  end

  entry.kind = kind
  for key, value in pairs(fields) do
    entry[key] = vim.deepcopy(value)
  end
  ui:_schedule_render()
  return entry
end

local function dirty_block_id(event, blocks)
  local kind = event and event.kind or nil
  local kind_type = kind and kind.type or nil
  if kind_type == "execution_state_changed" then
    return nil
  end
  if kind_type == "tool_call_started"
    or kind_type == "tool_call_arguments"
    or kind_type == "tool_call_finished"
  then
    return kind.tool_call_id and ("tool:" .. tostring(kind.tool_call_id)) or nil
  end
  if kind_type == "child_execution_started" or kind_type == "child_execution_finished" then
    return kind.child and ("child:" .. tostring(kind.child)) or nil
  end
  return blocks[#blocks] and blocks[#blocks].id or nil
end

function M.new(ui)
  return setmetatable({
    ui = assert(ui, "semantic projection renderer requires a UI"),
    rendered_count = 0,
  }, Renderer)
end

function Renderer:_render_block(block)
  local ui = self.ui
  if block.kind == "user_markdown" then
    update_entry(ui, block.id, "user", {
      label = "You",
      text = block.text or "",
    })
  elseif block.kind == "assistant_markdown" then
    update_entry(ui, block.id, "assistant", {
      text = block.text or "",
    })
  elseif block.kind == "reasoning" then
    update_entry(ui, block.id, "thinking", {
      text = block.text or "",
    })
  elseif block.kind == "tool_call" then
    ui:_tool({
      tool_call_id = block.tool_call_id,
      title = block.callable or block.tool_call_id,
      status = block.status,
      raw_input = block.arguments,
      raw_output = block.output,
    })
    ui:_schedule_render()
  elseif block.kind == "child_execution" then
    update_entry(ui, block.id, "system", {
      label = "Child execution",
      text = string.format(
        "%s · %s",
        tostring(block.child_execution_id),
        tostring(block.state or block.status)
      ),
    })
  elseif block.kind == "error" then
    update_entry(ui, block.id, "error", {
      text = block.text or block.code or "execution failed",
    })
  else
    error("unsupported semantic projection block: " .. tostring(block.kind))
  end
end

function Renderer:sync(blocks, event)
  blocks = blocks or {}
  local previous_count = self.rendered_count
  for index = previous_count + 1, #blocks do
    self:_render_block(blocks[index])
  end
  self.rendered_count = #blocks

  local dirty_id = dirty_block_id(event, blocks)
  if dirty_id and previous_count > 0 then
    for index = math.min(previous_count, #blocks), 1, -1 do
      local block = blocks[index]
      if block.id == dirty_id then
        self:_render_block(block)
        break
      end
    end
  end
end

function Renderer:replace(blocks)
  blocks = blocks or {}
  clear_ui_projection(self.ui)
  self.rendered_count = 0
  for _, block in ipairs(blocks) do
    self:_render_block(block)
  end
  self.rendered_count = #blocks
  self.ui:finish_response()
end

M.Renderer = Renderer
return M
