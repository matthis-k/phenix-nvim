local Store = require("phenix.store")
local Projection = require("phenix.projection")

local store = Store.new()
store:replace_snapshot({
  sessions = { { id = "session-1", default_target = { kind = "routed", value = "default" } } },
  executions = { { id = "execution-1", session_id = "session-1", state = "pending" } },
  last_event_sequence = 2,
})
assert(store.last_event_sequence == 2, "snapshot sequence was not installed")
assert(store.sessions["session-1"] ~= nil, "session snapshot was not indexed")
assert(store.executions["execution-1"].state == "pending", "execution snapshot was not indexed")

assert(store:apply_event({
  sequence = 2,
  session_id = "session-1",
  execution_id = "execution-1",
  kind = { type = "execution_state_changed", state = "running" },
}) == "duplicate", "duplicate event should be ignored")
assert(store.executions["execution-1"].state == "pending", "duplicate event mutated projected state")

local applied = store:apply_event({
  sequence = 3,
  session_id = "session-1",
  execution_id = "execution-1",
  kind = { type = "execution_state_changed", state = "running" },
})
assert(applied == "applied", "contiguous event was not applied")
assert(store.executions["execution-1"].state == "running", "execution state was not projected")

local status, gap = store:apply_event({
  sequence = 5,
  session_id = "session-1",
  execution_id = "execution-1",
  kind = { type = "reasoning_delta", text = "lost predecessor" },
})
assert(status == nil and gap.code == "sequence_gap", "event gap did not require resync")
assert(store.needs_resync == true, "store did not retain resync requirement")

store:replace_snapshot({ sessions = {}, executions = {}, last_event_sequence = 10 })
assert(store.needs_resync == false and store.last_event_sequence == 10, "fresh snapshot did not clear resync state")

local projection = Projection.new()
projection:apply_events({
  { sequence = 1, execution_id = "execution-1", kind = { type = "reasoning_delta", text = "think " } },
  { sequence = 2, execution_id = "execution-1", kind = { type = "tool_call_started", tool_call_id = "tool-1", callable = "tool.read" } },
  { sequence = 3, execution_id = "execution-1", kind = { type = "tool_call_arguments", tool_call_id = "tool-1", arguments = "{\n  \"path\": \"x\"\n}" } },
  { sequence = 4, execution_id = "execution-1", kind = { type = "tool_call_finished", tool_call_id = "tool-1", output = "ok\nline2", success = true } },
  { sequence = 5, execution_id = "execution-1", kind = { type = "reasoning_delta", text = "continue" } },
  { sequence = 6, execution_id = "execution-1", kind = { type = "assistant_content_delta", text = "answer" } },
})

assert(#projection.blocks == 4, "semantic projection unexpectedly regrouped blocks")
assert(projection.blocks[1].kind == "reasoning", "reasoning did not remain first")
assert(projection.blocks[2].kind == "tool_call", "tool call moved out of causal order")
assert(projection.blocks[3].kind == "reasoning", "reasoning after tool call was regrouped")
assert(projection.blocks[4].kind == "assistant_markdown", "assistant content moved out of causal order")
assert(projection.blocks[2].arguments:find("\n", 1, true), "multiline tool arguments were flattened")
assert(projection.blocks[2].output == "ok\nline2", "multiline tool result was flattened")
assert(projection.blocks[2].status == "completed", "tool result did not update stable tool block")
