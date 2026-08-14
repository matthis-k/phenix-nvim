local source = assert(debug.getinfo(1, "S").source:match("^@(.+)$"), "startup config source path unavailable")
local test_root = vim.fs.dirname(source)
local python = vim.fn.exepath("python3")
assert(python ~= "", "python3 is required for the startup ACP fixture")
local fixture = vim.fs.joinpath(test_root, "fixture_agent.py")
assert(vim.uv.fs_stat(fixture), "startup ACP fixture is missing")

phenix.acp.configure({
  definition_id = "phenix.startup-test",
  router = "router.startup-test",
  standard_session = {
    role = "coordinator",
    difficulty = "d0",
    objective = "Exercise the packaged Phenix conductor through a deterministic ACP backend",
  },
})

phenix.acp.backend({
  id = "fixture",
  command = python .. " " .. fixture,
})

phenix.acp.workflow({
  id = "workflow.startup-test",
  title = "Startup integration workflow",
  steps = {
    {
      key = "inspect",
      role = "scout",
      objective = "Inspect the deterministic fixture for {objective}",
    },
  },
})

local model = "fixture/fixture/fixture-model/minimal"
phenix.acp.routing_table({
  id = "router.startup-test",
  title = "Startup integration routing",
  routes = {
    {
      role = "*",
      workflow = "*",
      d0 = model,
      d1 = model,
      d2 = model,
      d3 = model,
      d4 = model,
      explanation = "Deterministic ACP fixture route",
    },
  },
})
