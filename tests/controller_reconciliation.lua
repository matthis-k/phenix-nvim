local Controller = require("phenix.controller")

local pending_after = nil
local pending_initialize = nil
local pending_submit = nil
local submit_calls = 0
local deliver_event = nil
local observed = {}

local controller = Controller.new({
  session_id = "session-1",
  client_factory = function(options)
    deliver_event = options.on_event
    return {
      initialize = function(_, after_sequence, callback)
        pending_after = after_sequence
        pending_initialize = callback
      end,
      submit = function(_, _, _, callback)
        submit_calls = submit_calls + 1
        pending_submit = callback
      end,
    }
  end,
  on_event = function(event)
    observed[#observed + 1] = event.sequence
  end,
})

local function snapshot(state, sequence)
  return {
    sessions = {
      {
        id = "session-1",
        default_target = { kind = "routed", value = "default" },
      },
    },
    executions = {
      {
        id = "execution-1",
        session_id = "session-1",
        parent_execution = nil,
        state = state,
      },
    },
    last_event_sequence = sequence,
  }
end

controller.store:replace_snapshot(snapshot("pending", 1))
controller.store:set_connection("connected")
controller.projection:apply_event({
  sequence = 1,
  session_id = "session-1",
  execution_id = "execution-1",
  kind = { type = "user_input", text = "hello" },
})

local refresh_finished = false
local refresh_error = nil
controller:_refresh_snapshot(function(err)
  refresh_finished = true
  refresh_error = err
end)

assert(pending_after == 1, "refresh did not use the current event sequence as its cursor")
assert(type(pending_initialize) == "function", "refresh did not issue an initialize cursor request")

local reasoning = {
  sequence = 2,
  session_id = "session-1",
  execution_id = "execution-1",
  kind = { type = "reasoning_delta", text = "think" },
}
local answer = {
  sequence = 3,
  session_id = "session-1",
  execution_id = "execution-1",
  kind = { type = "assistant_content_delta", text = "answer" },
}
local completed = {
  sequence = 4,
  session_id = "session-1",
  execution_id = "execution-1",
  kind = { type = "execution_state_changed", state = "completed" },
}

-- These live events overtake the synchronization response. Sequences 2-3 are
-- covered by the response snapshot/history; sequence 4 happened after the
-- snapshot was captured and must be replayed after it is installed.
deliver_event(reasoning)
deliver_event(answer)
deliver_event(completed)
assert(controller.store.last_event_sequence == 1, "live events were applied while reconciliation was buffered")

pending_initialize({
  type = "initialized",
  snapshot = snapshot("running", 3),
  events = { reasoning, answer },
  backends = {},
}, nil)

assert(refresh_finished and refresh_error == nil, "reconciliation did not complete successfully")
assert(controller.store.last_event_sequence == 4, "post-snapshot live event was not replayed")
assert(controller.store.executions["execution-1"].state == "completed", "snapshot replay regressed execution state")
assert(#controller.projection.blocks == 3, "reconciliation duplicated or lost semantic transcript blocks")
assert(controller.projection.blocks[2].kind == "reasoning" and controller.projection.blocks[2].text == "think")
assert(controller.projection.blocks[3].kind == "assistant_markdown" and controller.projection.blocks[3].text == "answer")
assert(vim.deep_equal(observed, { 2, 3, 4 }), "reconciled events were not published exactly once in sequence order")

-- A delayed copy of an event already covered by the synchronization response
-- must remain a transport duplicate rather than duplicating transcript output.
deliver_event(answer)
assert(#controller.projection.blocks == 3, "delayed covered event duplicated transcript output")
assert(vim.deep_equal(observed, { 2, 3, 4 }), "delayed covered event was published twice")

-- Reconciliation requests are serialized rather than reporting a successful
-- conductor mutation as a local synchronization-busy failure.
local first_refresh_done = false
local second_refresh_done = false
controller:_refresh_snapshot(function(err)
  assert(err == nil, "first queued refresh failed")
  first_refresh_done = true
end)
local first_refresh_reply = pending_initialize
controller:_refresh_snapshot(function(err)
  assert(err == nil, "second queued refresh failed")
  second_refresh_done = true
end)
assert(not first_refresh_done and not second_refresh_done, "refresh completed before its reply")
first_refresh_reply({ type = "initialized", snapshot = snapshot("completed", 4), events = {}, backends = {} }, nil)
assert(first_refresh_done and not second_refresh_done, "queued refresh was not serialized")
local second_refresh_reply = pending_initialize
assert(second_refresh_reply ~= first_refresh_reply, "queued refresh did not issue a fresh cursor barrier")
second_refresh_reply({ type = "initialized", snapshot = snapshot("completed", 4), events = {}, backends = {} }, nil)
assert(second_refresh_done, "queued refresh never completed")

-- Child activity must not replace the session's root execution for cancel/
-- activity decisions.
controller.store.executions["execution-child"] = {
  id = "execution-child",
  session_id = "session-1",
  parent_execution = "execution-1",
  state = "running",
}
assert(controller:activity_state() == "settled", "child execution was mistaken for the active session root")

-- State-changing commands are serialized before the conductor request is sent,
-- closing the double-submit window while a previous mutation is unresolved.
-- An accepted in-flight submission is execution activity even before the
-- conductor reply/snapshot has exposed its root execution; otherwise callers
-- can observe a false settled state and race transcript/follow-up handling.
local first_submit_error = nil
assert(controller:submit("first", function(_, err)
  first_submit_error = err
end), "first submit was rejected")
assert(submit_calls == 1 and type(pending_submit) == "function", "first submit did not reach the conductor client")
assert(controller:activity_state() == "running", "in-flight submit was exposed as settled before reconciliation")
local second_submit_error = nil
assert(not controller:submit("second", function(_, err)
  second_submit_error = err
end), "second submit bypassed the mutation gate")
assert(submit_calls == 1, "second submit reached the conductor while the first was unresolved")
assert(second_submit_error and second_submit_error.code == "frontend_busy", "second submit did not report frontend_busy")
assert(first_submit_error == nil, "unresolved first submit unexpectedly completed")

pending_submit(nil, { code = "fixture_rejected", message = "fixture submit rejected" })
assert(first_submit_error and first_submit_error.code == "fixture_rejected", "submit failure was not returned to caller")
assert(controller:activity_state() == "settled", "failed in-flight submit left frontend activity running")

print("N5 controller reconciliation invariants passed")