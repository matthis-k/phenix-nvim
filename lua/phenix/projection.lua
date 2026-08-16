local M = {}
local Projection = {}
Projection.__index = Projection

local function append_block(self, block)
  self.blocks[#self.blocks + 1] = block
  return block
end

local function event_id(event)
  return "event:" .. tostring(event.sequence)
end

function M.new()
  return setmetatable({
    blocks = {},
    tools = {},
    children = {},
  }, Projection)
end

function Projection:apply_event(event)
  assert(type(event) == "table" and type(event.sequence) == "number", "invalid execution event")
  local kind = assert(event.kind, "execution event kind is missing")
  local kind_type = assert(kind.type, "execution event kind type is missing")
  local last = self.blocks[#self.blocks]

  if kind_type == "user_input" then
    append_block(self, {
      id = event_id(event),
      kind = "user_markdown",
      execution_id = event.execution_id,
      text = kind.text,
    })
  elseif kind_type == "assistant_content_delta" then
    if last and last.kind == "assistant_markdown" and last.execution_id == event.execution_id then
      last.text = last.text .. kind.text
    else
      append_block(self, {
        id = event_id(event),
        kind = "assistant_markdown",
        execution_id = event.execution_id,
        text = kind.text,
      })
    end
  elseif kind_type == "reasoning_delta" then
    if last and last.kind == "reasoning" and last.execution_id == event.execution_id then
      last.text = last.text .. kind.text
    else
      append_block(self, {
        id = event_id(event),
        kind = "reasoning",
        execution_id = event.execution_id,
        text = kind.text,
        foldable = true,
      })
    end
  elseif kind_type == "tool_call_started" then
    local block = append_block(self, {
      id = "tool:" .. kind.tool_call_id,
      kind = "tool_call",
      execution_id = event.execution_id,
      tool_call_id = kind.tool_call_id,
      callable = kind.callable,
      arguments = "",
      status = "running",
      foldable = true,
    })
    self.tools[kind.tool_call_id] = block
  elseif kind_type == "tool_call_arguments" then
    local block = assert(self.tools[kind.tool_call_id], "tool arguments arrived before tool start")
    block.arguments = block.arguments .. kind.arguments
  elseif kind_type == "tool_call_finished" then
    local block = assert(self.tools[kind.tool_call_id], "tool result arrived before tool start")
    block.output = kind.output
    block.success = kind.success
    block.status = kind.success and "completed" or "failed"
  elseif kind_type == "child_execution_started" then
    local block = append_block(self, {
      id = "child:" .. kind.child,
      kind = "child_execution",
      execution_id = event.execution_id,
      child_execution_id = kind.child,
      status = "running",
      foldable = true,
    })
    self.children[kind.child] = block
  elseif kind_type == "child_execution_finished" then
    local block = assert(self.children[kind.child], "child finish arrived before child start")
    block.state = kind.state
    block.status = "finished"
  elseif kind_type == "error" then
    append_block(self, {
      id = event_id(event),
      kind = "error",
      execution_id = event.execution_id,
      code = kind.code,
      text = kind.message,
    })
  elseif kind_type ~= "execution_state_changed" then
    error("unsupported execution event kind: " .. tostring(kind_type))
  end

  return self.blocks
end

function Projection:apply_events(events)
  for _, event in ipairs(events) do
    self:apply_event(event)
  end
  return self.blocks
end

M.Projection = Projection
return M
