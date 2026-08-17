from pathlib import Path


def replace(path, old, new, label):
    file = Path(path)
    source = file.read_text()
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    file.write_text(source.replace(old, new, 1))


replace(
    "lua/phenix/session.lua",
    '      if type(model.target) == "table" then\n',
    '      if type(model.target) == "table" and model.selectable ~= false then\n',
    "model picker filter",
)

replace(
    "tests/fixture_conductor.py",
    '        {"target": MODEL, "name": "Fixture Model"},\n        {"target": ALT_MODEL, "name": "Fixture Alt"},\n',
    '        {"target": MODEL, "name": "Fixture Model", "selectable": False},\n        {"target": ALT_MODEL, "name": "Fixture Alt", "selectable": True},\n',
    "fixture model selectability",
)

replace(
    "tests/startup.lua",
    'assert(state.session.default_target.value.model == "fixture-model", "packaged controller selected the wrong target")\n\nlocal mutation_done = false\n',
    '''assert(state.session.default_target.value.model == "fixture-model", "packaged controller selected the wrong target")

local original_ui_select = vim.ui.select
local model_choices = nil
vim.ui.select = function(items, options, callback)
  assert(options.prompt == "Model", "unexpected picker while testing model selection")
  model_choices = vim.deepcopy(items)
  callback(nil)
end
assert(session:select_model(), "model picker was rejected")
vim.ui.select = original_ui_select
assert(type(model_choices) == "table" and #model_choices == 1, "model picker did not filter unauthenticated providers")
assert(model_choices[1].target.value.model == "fixture-alt", "model picker retained the non-selectable fixture model")

local mutation_done = false
''',
    "startup model picker assertion",
)
