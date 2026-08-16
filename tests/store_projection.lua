local Store = require("phenix.store")
local Projection = require("phenix.projection")
local ExecutionTree = require("phenix.execution_tree")
local Controller = require("phenix.controller")

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

local rows = ExecutionTree.project("session-1", {
  {
    id = "execution-4",
    session_id = "session-1",
    parent_execution = "execution-2",
    kind = "agent",
    callable = "agent.verify",
    state = "pending",
    target = { kind = "routed", value = "default" },
  },
  {
    id = "execution-2",
    session_id = "session-1",
    parent_execution = "execution-1",
    kind = "workflow",
    callable = "workflow.implement",
    state = "running",
    target = { kind = "fixed", value = { backend = "pi", provider = "openai", model = "gpt" } },
  },
  {
    id = "execution-1",
    session_id = "session-1",
    kind = "root",
    state = "running",
    target = { kind = "routed", value = "default" },
  },
  {
    id = "execution-3",
    session_id = "other-session",
    kind = "root",
    state = "completed",
  },
})
assert(#rows == 3, "execution tree leaked another session")
assert(rows[1].id == "execution-1" and rows[1].depth == 0, "execution tree root order is unstable")
assert(rows[2].id == "execution-2" and rows[2].depth == 1, "workflow was not nested under its parent")
assert(rows[3].id == "execution-4" and rows[3].depth == 2, "agent was not nested under workflow")
assert(rows[2].label:find("workflow.implement", 1, true), "execution tree omitted callable identity")
assert(rows[2].label:find("pi/openai/gpt", 1, true), "execution tree omitted fixed target")
assert(rows[3].label:find("routing/default", 1, true), "execution tree omitted routed target")

local session_one = {
  id = "session-1",
  name = "one",
  config_revision = "fixture-revision",
  default_target = { kind = "routed", value = "default" },
}
local session_two = {
  id = "session-2",
  name = "two",
  config_revision = "fixture-revision",
  default_target = { kind = "routed", value = "default" },
}
local history = {
  {
    sequence = 1,
    session_id = "session-1",
    execution_id = "execution-one",
    kind = { type = "user_input", text = "only session one" },
  },
  {
    sequence = 2,
    session_id = "session-2",
    execution_id = "execution-two",
    kind = { type = "user_input", text = "only session two" },
  },
}
local history_controller = Controller.new({
  client_factory = function()
    return {
      persistent = true,
      start = function(_, _, callback)
        callback({
          type = "initialized",
          snapshot = {
            sessions = { session_one, session_two },
            executions = {
              { id = "execution-one", session_id = "session-1", state = "completed" },
              { id = "execution-two", session_id = "session-2", state = "completed" },
            },
            last_event_sequence = 2,
          },
          events = history,
          backends = {},
        }, nil)
      end,
      stop = function() end,
    }
  end,
  select_existing_session = function(sessions, callback)
    assert(#sessions == 2, "history selector did not receive both sessions")
    callback({ kind = "existing", session_id = "session-2" }, nil)
  end,
})
local history_ready = nil
history_controller:start(function(session, err)
  assert(err == nil, "multi-session history controller failed to start")
  history_ready = session
end)
assert(history_ready and history_ready.id == "session-2", "multi-session startup selected wrong history")
local selected_blocks = history_controller:projection_blocks()
assert(#selected_blocks == 1 and selected_blocks[1].text == "only session two", "selected session leaked another transcript")
local switched = assert(history_controller:use_session("session-1"))
assert(switched.id == "session-1", "session switch failed")
local switched_blocks = history_controller:projection_blocks()
assert(#switched_blocks == 1 and switched_blocks[1].text == "only session one", "session switch retained previous transcript")

print("N8 store/projection/execution-tree/session-isolation invariants passed")
