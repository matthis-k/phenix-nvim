local source = assert(debug.getinfo(1, "S").source:match("^@(.+)$"), "startup test source path unavailable")
local test_root = vim.fs.dirname(source)
local fixture = vim.fs.joinpath(test_root, "fixture_conductor.py")
local python = vim.fn.exepath("python3")

assert(python ~= "", "python3 is unavailable")
assert(vim.uv.fs_stat(fixture), "native conductor fixture is missing: " .. fixture)
assert(vim.g.loaded_phenix == 1, "packaged Phenix plugin was not loaded")
assert(vim.g.loaded_phenix_acp == nil, "legacy ACP plugin marker is still active")
local packaged_conductor = assert(vim.env.PHENIX_CONDUCTOR_COMMAND, "packaged conductor command is unavailable")
assert(packaged_conductor:match("/bin/phenix%-conductor$"), "packaged frontend does not launch bare phenix-conductor: " .. packaged_conductor)
assert(not packaged_conductor:find("phenix%-conductor%-nvim"), "legacy frontend-composed conductor survived packaging")
assert(not packaged_conductor:find("pi%-acp"), "Pi ACP backend leaked into the default frontend path")

local config_directory = require("nix-info").settings.config_directory
assert(type(config_directory) == "string", "nix wrapper config_directory was not serialized as a string")
assert(type(_G.Phenix) == "table", "global Phenix registry was not initialized")
assert(type(Phenix.api) == "table" and type(Phenix.require_api) == "function", "Phenix API facade is unavailable")
assert(Phenix.api.acp == nil, "ACP protocol survived in the packaged feature registry")

local phenix = require("phenix")
assert(Phenix.api.agent == phenix, "packaged native agent frontend was not registered")

local default_session = phenix.toggle({ fullscreen = true })
local default_initialized = vim.wait(5000, function()
  local state = default_session.controller:state()
  return state.connection == "connected" and type(state.catalogs) == "table" and #state.catalogs > 0
end, 20)
assert(
  default_initialized,
  "packaged default conductor did not initialize\nstate: "
    .. vim.inspect(default_session.controller:state())
    .. "\ntranscript: "
    .. default_session.ui:text()
)
local default_state = assert(phenix.state(), "default conductor state is unavailable")
assert(default_state.connection == "connected", "packaged default conductor did not connect")
local default_catalog = nil
for _, catalog in ipairs(default_state.catalogs or {}) do
  if catalog.backend == "phenix" then
    default_catalog = catalog
    break
  end
end
assert(default_catalog ~= nil, "packaged default conductor did not expose the Phenix backend")
assert(type(default_catalog.models) == "table" and #default_catalog.models > 0, "Phenix backend exposed no default model target")
phenix.shutdown()
assert(phenix.current() == nil, "default conductor session survived shutdown")
assert(Phenix.require_api("agent") == phenix, "packaged typed frontend lookup failed")
assert(vim.fn.maparg(" o", "n") == "", "OpenCode mapping survived removal")

for _, method in ipairs({
  "fork",
  "rename",
  "set_target",
  "refresh_backend",
  "refresh_catalogs",
  "refresh_callables",
  "callables",
  "run_callable",
  "select_callable",
  "fixed_target",
  "routed_target",
  "state",
}) do
  assert(type(phenix[method]) == "function", "native Phenix frontend is missing semantic action: " .. method)
end
for _, plug in ipairs({
  "<Plug>(phenix-cancel)",
  "<Plug>(phenix-fork-session)",
  "<Plug>(phenix-rename-session)",
  "<Plug>(phenix-refresh-catalogs)",
  "<Plug>(phenix-select-callable)",
  "<Plug>(phenix-refresh-callables)",
}) do
  assert(vim.fn.maparg(plug, "n", false, true).lhs ~= "", "native Phenix frontend did not expose " .. plug)
end
assert(vim.fn.maparg(" pc", "n", false, true).rhs == "<Plug>(phenix-cancel)", "distribution does not map through the public agent action")

phenix.setup({
  conductor_command = { python, fixture },
  conductor_cwd_arg = false,
})

local session = phenix.toggle({ fullscreen = true })
local ready = vim.wait(5000, function()
  return session:is_ready()
end, 20)
assert(
  ready,
  "packaged native conductor session did not become ready\nstate: "
    .. vim.inspect(session.controller:state())
    .. "\ntranscript: "
    .. session.ui:text()
)

local state = assert(phenix.state(), "public frontend state is unavailable")
assert(state.connection == "connected", "packaged controller did not connect")
assert(state.session ~= nil, "packaged controller did not create a session")
assert(state.session.default_target.value.model == "fixture-model", "packaged controller selected the wrong target")

local mutation_done = false
assert(phenix.set_target(phenix.routed_target("startup-route"), function(_, err)
  assert(err == nil, "routed target mutation failed: " .. vim.inspect(err))
  mutation_done = true
end), "public routed target mutation was rejected")
assert(vim.wait(5000, function() return mutation_done end, 20), "routed target mutation did not complete")
assert(phenix.state().session.default_target.kind == "routed", "routed target was not projected")
assert(phenix.state().session.default_target.value == "startup-route", "wrong routed profile was projected")

local model = phenix.state().catalogs[1].models[2].target
mutation_done = false
assert(phenix.set_target(phenix.fixed_target(model.backend, model.provider, model.model, model.inference), function(_, err)
  assert(err == nil, "fixed target mutation failed: " .. vim.inspect(err))
  mutation_done = true
end), "public fixed target mutation was rejected")
assert(vim.wait(5000, function() return mutation_done end, 20), "fixed target mutation did not complete")
assert(phenix.state().session.default_target.value.model == "fixture-alt", "fixed target was not projected")

local refreshed = false
assert(phenix.refresh_catalogs(function(catalogs, err)
  assert(err == nil, "catalog refresh failed: " .. vim.inspect(err))
  assert(type(catalogs) == "table" and catalogs[1] ~= nil, "catalog refresh returned no catalogs")
  refreshed = true
end), "public catalog refresh was rejected")
assert(vim.wait(5000, function() return refreshed end, 20), "catalog refresh did not complete")

local callables_refreshed = false
assert(phenix.refresh_callables(function(callables, err)
  assert(err == nil, "callable catalog refresh failed: " .. vim.inspect(err))
  assert(#callables == 3, "callable catalog did not expose all fixture descriptors")
  callables_refreshed = true
end), "public callable catalog refresh was rejected")
assert(vim.wait(5000, function() return callables_refreshed end, 20), "callable catalog refresh did not complete")
local callables = phenix.callables()
assert(#callables == 3, "public callable catalog cache has the wrong size")
assert(callables[1].id == "agent.fixture" and callables[1].kind == "agent", "agent descriptor was not typed/sorted")
assert(callables[2].id == "tool.fixture" and callables[2].kind == "tool", "tool descriptor was not typed/sorted")
assert(callables[3].id == "workflow.fixture" and callables[3].kind == "workflow", "workflow descriptor was not typed/sorted")
assert(#phenix.state().callables == 3, "public frontend state omitted callable catalog")

local tool_error = nil
assert(not phenix.run_callable("tool.fixture", "must not start", function(_, err)
  tool_error = err
end), "tool descriptor was incorrectly startable as a top-level execution")
assert(tool_error and tool_error.code == "callable_not_startable", "tool start rejection used the wrong semantic error")

assert(session:prompt("rich transcript"), "semantic transcript prompt was rejected")
assert(vim.wait(5000, function()
  return session:activity_state() == "settled"
end, 20), "semantic transcript prompt did not settle")
session.ui:_flush_render()
local transcript = session.ui:text()
local reasoning_at = assert(transcript:find("thinking about: rich transcript", 1, true), "reasoning block was not rendered")
local tool_at = assert(transcript:find("### Tool · read README · completed", 1, true), "tool block was not rendered")
local answer_at = assert(transcript:find("echo: rich transcript", 1, true), "assistant block was not rendered")
assert(reasoning_at < tool_at and tool_at < answer_at, "semantic projection order was not preserved")
local first_line_at = assert(transcript:find("first line", 1, true), "first multiline tool argument line was not rendered")
local second_line_at = assert(transcript:find("second line", 1, true), "second multiline tool argument line was not rendered")
assert(first_line_at < second_line_at, "multiline tool argument order was not preserved")
assert(not transcript:find("pi v", 1, true), "native semantic rendering leaked Pi startup-banner handling")

local callable_execution = nil
assert(phenix.run_callable("agent.fixture", "inspect callable frontier", function(execution, err)
  assert(err == nil, "callable execution failed: " .. vim.inspect(err))
  callable_execution = execution
end), "typed callable execution was rejected")
assert(session:activity_state() == "running", "accepted callable start was exposed as settled before reconciliation")
assert(vim.wait(5000, function()
  return callable_execution ~= nil and session:activity_state() == "settled"
end, 20), "typed callable execution did not settle")
assert(callable_execution.kind == "agent" and callable_execution.callable == "agent.fixture", "wrong callable execution was returned")
session.ui:_flush_render()
transcript = session.ui:text()
local callable_user_at = assert(
  transcript:find("## You\n\ninspect callable frontier", 1, true),
  "canonical callable objective was not rendered as user input"
)
local callable_reasoning_at = assert(
  transcript:find("agent.fixture reasoning: inspect callable frontier", 1, true),
  "callable reasoning was not rendered"
)
local callable_result_at = assert(
  transcript:find("agent.fixture result: inspect callable frontier", 1, true),
  "callable result was not rendered"
)
assert(
  callable_user_at < callable_reasoning_at and callable_reasoning_at < callable_result_at,
  "callable objective/reasoning/result causal order was not preserved"
)
assert(
  select(2, transcript:gsub("## You\n\ninspect callable frontier", "")) == 1,
  "callable objective was rendered more than once as user input"
)

assert(phenix.toggle_info(), "semantic execution-tree view did not open")
assert(session.execution_tree_view:is_visible(), "execution-tree buffer was not shown in the transcript pane")
local tree_text = table.concat(
  vim.api.nvim_buf_get_lines(session.execution_tree_view.buffer, 0, -1, false),
  "\n"
)
assert(tree_text:find("[completed] root", 1, true), "execution-tree view omitted root lifecycle state")
assert(tree_text:find("[completed] agent.fixture", 1, true), "execution-tree view omitted typed callable execution")
assert(tree_text:find("fixture-alt", 1, true), "execution-tree view omitted the typed execution target")
assert(phenix.toggle_info(), "semantic execution-tree view did not close")
assert(
  vim.api.nvim_win_get_buf(session.ui.transcript_window) == session.ui.transcript_buffer,
  "closing execution-tree view did not restore the transcript"
)

local original_session = session.session_id
local forked = nil
assert(phenix.fork("startup fork", function(summary, err)
  assert(err == nil, "session fork failed: " .. vim.inspect(err))
  forked = summary
end), "public session fork was rejected")
assert(vim.wait(5000, function() return forked ~= nil end, 20), "session fork did not complete")
assert(forked.id ~= original_session, "fork reused the source session identity")
assert(forked.parent_session == original_session, "fork did not preserve source-session lineage")
assert(session.session_id == forked.id, "frontend did not switch to the forked session")

local renamed = nil
assert(phenix.rename("startup renamed", function(summary, err)
  assert(err == nil, "session rename failed: " .. vim.inspect(err))
  renamed = summary
end), "public session rename was rejected")
assert(vim.wait(5000, function() return renamed ~= nil end, 20), "session rename did not complete")
assert(phenix.state().session.name == "startup renamed", "renamed session was not projected")

phenix.toggle()
assert(not session.ui:is_visible(), "native frontend did not hide its UI group")
assert(session.controller:state().connection == "connected", "hiding the UI changed conductor connection state")
phenix.toggle()
assert(session.ui:is_visible(), "native frontend did not restore its UI group")

phenix.shutdown()
assert(phenix.current() == nil, "packaged session survived shutdown")

print("N6 callable discovery/execution packaged startup passed")
vim.cmd("qa!")
