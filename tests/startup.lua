local source = assert(debug.getinfo(1, "S").source:match("^@(.+)$"), "startup test source path unavailable")
local test_root = vim.fs.dirname(source)
local fixture = vim.fs.joinpath(test_root, "fixture_conductor.py")
local python = vim.fn.exepath("python3")

assert(python ~= "", "python3 is unavailable")
assert(vim.uv.fs_stat(fixture), "native conductor fixture is missing: " .. fixture)
assert(vim.g.loaded_phenix == 1, "packaged Phenix plugin was not loaded")
assert(vim.g.loaded_phenix_acp == nil, "legacy ACP plugin marker is still active")

local config_directory = require("nix-info").settings.config_directory
assert(type(config_directory) == "string", "nix wrapper config_directory was not serialized as a string")
assert(type(_G.Phenix) == "table", "global Phenix registry was not initialized")
assert(type(Phenix.api) == "table" and type(Phenix.require_api) == "function", "Phenix API facade is unavailable")
assert(Phenix.api.acp == nil, "ACP protocol survived in the packaged feature registry")

local phenix = require("phenix")
assert(Phenix.api.agent == phenix, "packaged native agent frontend was not registered")
assert(Phenix.require_api("agent") == phenix, "packaged typed frontend lookup failed")
assert(vim.fn.maparg(" o", "n") == "", "OpenCode mapping survived removal")

for _, method in ipairs({
  "fork",
  "rename",
  "set_target",
  "refresh_backend",
  "refresh_catalogs",
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

print("N6 packaged conductor feature startup passed")
vim.cmd("qa!")
