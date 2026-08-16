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

local cancel_plug = vim.fn.maparg("<Plug>(phenix-cancel)", "n", false, true)
assert(cancel_plug.lhs ~= "", "native Phenix frontend did not expose cancel")
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

local state = session.controller:state()
assert(state.connection == "connected", "packaged controller did not connect")
assert(state.session ~= nil, "packaged controller did not create a session")
assert(state.session.default_target.value.model == "fixture-model", "packaged controller selected the wrong target")

phenix.toggle()
assert(not session.ui:is_visible(), "native frontend did not hide its UI group")
assert(session.controller:state().connection == "connected", "hiding the UI changed conductor connection state")
phenix.toggle()
assert(session.ui:is_visible(), "native frontend did not restore its UI group")

phenix.shutdown()
assert(phenix.current() == nil, "packaged session survived shutdown")

print("N4 packaged native startup passed")
vim.cmd("qa!")