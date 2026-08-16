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

local fixed_target = {
  kind = "fixed",
  value = {
    backend = "fixture",
    provider = "fixture",
    model = "fixture-model",
    inference = {},
  },
}
local backend_catalog = {
  backend = "fixture",
  models = {
    { target = vim.deepcopy(fixed_target.value), name = "Fixture Model" },
  },
  authentication_state = "not_required",
  authentication_methods = {},
}

local function startup_session(id, name)
  return {
    id = id,
    name = name,
    config_revision = "fixture-revision",
    default_target = vim.deepcopy(fixed_target),
  }
end

local function startup_case(options)
  options = options or {}
  local sessions = vim.deepcopy(options.sessions or {})
  local create_calls = 0
  local selector_calls = 0
  local selected_ids = nil
  local next_session = #sessions + 1

  local function startup_snapshot()
    return {
      sessions = vim.deepcopy(sessions),
      executions = {},
      last_event_sequence = 0,
    }
  end

  local fake_client = {
    persistent = options.persistent ~= false,
    start = function(_, _, callback)
      callback({
        type = "initialized",
        snapshot = startup_snapshot(),
        events = {},
        backends = { backend_catalog },
      }, nil)
    end,
    initialize = function(_, _, callback)
      callback({
        type = "initialized",
        snapshot = startup_snapshot(),
        events = {},
        backends = { backend_catalog },
      }, nil)
    end,
    create_session = function(_, create_options, callback)
      create_calls = create_calls + 1
      local session = startup_session("session-" .. next_session, nil)
      session.default_target = vim.deepcopy(create_options.target)
      next_session = next_session + 1
      sessions[#sessions + 1] = session
      callback({ type = "session", session = vim.deepcopy(session) }, nil)
    end,
    stop = function() end,
  }

  local controller_options = {
    session_id = options.session_id,
    target = options.target,
    client_factory = function()
      return fake_client
    end,
    select_existing_session = options.selection and function(candidates, callback)
      selector_calls = selector_calls + 1
      selected_ids = vim.tbl_map(function(session)
        return session.id
      end, candidates)
      callback(vim.deepcopy(options.selection), nil)
    end or nil,
  }
  local startup = Controller.new(controller_options)
  local ready_session = nil
  local startup_error = nil
  startup:start(function(session, err)
    ready_session = session
    startup_error = err
  end)
  return {
    controller = startup,
    session = ready_session,
    error = startup_error,
    create_calls = create_calls,
    selector_calls = selector_calls,
    selected_ids = selected_ids,
  }
end

local sole = startup_case({
  sessions = { startup_session("session-1", "only") },
})
assert(sole.error == nil and sole.session.id == "session-1", "persistent startup did not auto-resume sole session")
assert(sole.create_calls == 0 and sole.selector_calls == 0, "sole-session resume created or selected unnecessarily")

local explicit_target = startup_case({
  sessions = { startup_session("session-1", "old") },
  target = fixed_target,
})
assert(explicit_target.error == nil and explicit_target.session.id == "session-2", "explicit target did not create a new session")
assert(explicit_target.create_calls == 1, "explicit target unexpectedly reused persisted session")

local selected_existing = startup_case({
  sessions = {
    startup_session("session-2", "second"),
    startup_session("session-1", "first"),
  },
  selection = { kind = "existing", session_id = "session-2" },
})
assert(selected_existing.error == nil and selected_existing.session.id == "session-2", "multi-session selector chose wrong session")
assert(selected_existing.create_calls == 0 and selected_existing.selector_calls == 1, "existing selection created a new session")
assert(vim.deep_equal(selected_existing.selected_ids, { "session-1", "session-2" }), "selector input order was not deterministic")

local selected_new = startup_case({
  sessions = {
    startup_session("session-1", "first"),
    startup_session("session-2", "second"),
  },
  selection = { kind = "new" },
})
assert(selected_new.error == nil and selected_new.session.id == "session-3", "new-session selection did not create session")
assert(selected_new.create_calls == 1 and selected_new.selector_calls == 1, "new-session selection did not use selector/create path once")

local explicit_session = startup_case({
  sessions = {
    startup_session("session-1", "first"),
    startup_session("session-2", "second"),
  },
  session_id = "session-2",
  selection = { kind = "existing", session_id = "session-1" },
})
assert(explicit_session.error == nil and explicit_session.session.id == "session-2", "explicit session_id did not win startup selection")
assert(explicit_session.create_calls == 0 and explicit_session.selector_calls == 0, "explicit session_id still invoked selector/create path")

print("N8 controller reconciliation and persistent session startup invariants passed")