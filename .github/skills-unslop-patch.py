from pathlib import Path


def patch(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one anchor in {path}, found {count}: {old[:100]!r}")
    file.write_text(text.replace(old, new, 1))


# Conductor protocol client: expose the typed skill catalog request.
patch(
    "lua/phenix/conductor.lua",
    '''function Client:get_callable_catalog(callback)\n  return self:_request({ type = "get_callable_catalog" }, callback)\nend\n\nfunction Client:get_routing_catalog(callback)\n''',
    '''function Client:get_callable_catalog(callback)\n  return self:_request({ type = "get_callable_catalog" }, callback)\nend\n\nfunction Client:get_skill_catalog(callback)\n  return self:_request({ type = "get_skill_catalog" }, callback)\nend\n\nfunction Client:get_routing_catalog(callback)\n''',
)

# Controller: validate conductor-owned descriptors and cache the catalog.
patch(
    "lua/phenix/controller_actions.lua",
    '''local function validate_callable_catalog(result)\n''',
    '''local function validate_skill_catalog(result)\n  if type(result) ~= "table" or result.type ~= "skill_catalog" or not vim.islist(result.skills) then\n    return nil, { code = "invalid_skill_catalog", message = "conductor returned an invalid skill catalog" }\n  end\n  local skills = {}\n  local seen = {}\n  for _, descriptor in ipairs(result.skills) do\n    if type(descriptor) ~= "table"\n      or type(descriptor.id) ~= "string"\n      or vim.trim(descriptor.id) == ""\n      or type(descriptor.name) ~= "string"\n      or vim.trim(descriptor.name) == ""\n      or type(descriptor.description) ~= "string"\n      or (descriptor.invocation ~= "model_eligible" and descriptor.invocation ~= "manual_only")\n    then\n      return nil, { code = "invalid_skill_catalog", message = "skill catalog contains an invalid descriptor" }\n    end\n    if seen[descriptor.id] then\n      return nil, { code = "invalid_skill_catalog", message = "skill catalog contains duplicate id: " .. descriptor.id }\n    end\n    seen[descriptor.id] = true\n    skills[#skills + 1] = vim.deepcopy(descriptor)\n  end\n  table.sort(skills, function(left, right)\n    return left.id < right.id\n  end)\n  return skills, nil\nend\n\nlocal function validate_callable_catalog(result)\n''',
)
patch(
    "lua/phenix/controller_actions.lua",
    '''function Controller:refresh_callables(callback)\n''',
    '''function Controller:refresh_skills(callback)\n  callback = callback or function() end\n  return self.client:get_skill_catalog(function(result, error_value)\n    if error_value then\n      callback(nil, error_value)\n      return\n    end\n    local skills, validation_error = validate_skill_catalog(result)\n    if validation_error then\n      callback(nil, validation_error)\n      return\n    end\n    self.skills = skills\n    callback(vim.deepcopy(skills), nil)\n  end)\nend\n\nfunction Controller:refresh_callables(callback)\n''',
)

# Session facade: expose catalog state and an explicit skill picker.
patch(
    "lua/phenix/session_actions.lua",
    '''  state.callables = vim.deepcopy(self.controller.callables or {})\n  return state\nend\n''',
    '''  state.callables = vim.deepcopy(self.controller.callables or {})\n  state.skills = vim.deepcopy(self.controller.skills or {})\n  return state\nend\n''',
)
patch(
    "lua/phenix/session_actions.lua",
    '''function Session:callables()\n  return vim.deepcopy(self.controller.callables or {})\nend\n\nfunction Session:refresh_catalogs(callback)\n''',
    '''function Session:callables()\n  return vim.deepcopy(self.controller.callables or {})\nend\n\nfunction Session:skills()\n  return vim.deepcopy(self.controller.skills or {})\nend\n\nfunction Session:refresh_skills(callback)\n  if not self:is_ready() then\n    vim.notify("Phenix: session is not ready", vim.log.levels.WARN)\n    return false\n  end\n  self.controller:refresh_skills(function(skills, error_value)\n    if error_value then\n      self.ui:append_error(format_error("skill catalog refresh failed", error_value))\n    end\n    if callback then\n      callback(skills, error_value)\n    end\n  end)\n  return true\nend\n\nfunction Session:select_skill()\n  if not self:is_ready() then\n    vim.notify("Phenix: session is not ready", vim.log.levels.WARN)\n    return false\n  end\n\n  local function open_picker(skills)\n    if #skills == 0 then\n      vim.notify("Phenix: conductor exposes no skills", vim.log.levels.WARN)\n      return\n    end\n    vim.ui.select(skills, {\n      prompt = "Skill",\n      format_item = function(skill)\n        local invocation = skill.invocation == "manual_only" and "manual" or "automatic"\n        return string.format("%s · %s · %s", skill.name, invocation, skill.description)\n      end,\n    }, function(skill)\n      if not skill then\n        return\n      end\n      vim.ui.input({ prompt = string.format("%s objective: ", skill.name) }, function(objective)\n        if type(objective) ~= "string" or vim.trim(objective) == "" then\n          return\n        end\n        self:prompt(string.format("/skill %s %s", skill.id, objective))\n      end)\n    end)\n  end\n\n  local skills = self:skills()\n  if #skills > 0 then\n    open_picker(skills)\n    return true\n  end\n  return self:refresh_skills(function(refreshed, error_value)\n    if not error_value then\n      open_picker(refreshed or {})\n    end\n  end)\nend\n\nfunction Session:refresh_catalogs(callback)\n''',
)

# Public API and plug mappings.
patch(
    "lua/phenix/init.lua",
    '''function M.select_callable()\n  local current = current_session()\n  return current ~= nil and current:select_callable() or false\nend\n\n---@return boolean\nfunction M.authenticate()\n''',
    '''function M.select_callable()\n  local current = current_session()\n  return current ~= nil and current:select_callable() or false\nend\n\n---@return boolean\nfunction M.select_skill()\n  local current = current_session()\n  return current ~= nil and current:select_skill() or false\nend\n\n---@return boolean\nfunction M.authenticate()\n''',
)
patch(
    "lua/phenix/init.lua",
    '''function M.callables()\n  local current = current_session()\n  return current and current:callables() or {}\nend\n\n---@param callable_id string\n''',
    '''function M.callables()\n  local current = current_session()\n  return current and current:callables() or {}\nend\n\n---@return table[]\nfunction M.skills()\n  local current = current_session()\n  return current and current:skills() or {}\nend\n\n---@param callable_id string\n''',
)
patch(
    "lua/phenix/init.lua",
    '''function M.refresh_callables(callback)\n  local current = current_session()\n  return current ~= nil and current:refresh_callables(callback) or false\nend\n\n---@param name? string\n''',
    '''function M.refresh_callables(callback)\n  local current = current_session()\n  return current ~= nil and current:refresh_callables(callback) or false\nend\n\n---@param callback? function\n---@return boolean\nfunction M.refresh_skills(callback)\n  local current = current_session()\n  return current ~= nil and current:refresh_skills(callback) or false\nend\n\n---@param name? string\n''',
)
patch(
    "lua/phenix/mappings.lua",
    '''  ["<Plug>(phenix-select-callable)"] = { "select_callable", "Phenix: select callable" },\n  ["<Plug>(phenix-authenticate)"] = { "authenticate", "Phenix: authenticate provider" },\n''',
    '''  ["<Plug>(phenix-select-callable)"] = { "select_callable", "Phenix: select callable" },\n  ["<Plug>(phenix-select-skill)"] = { "select_skill", "Phenix: select skill" },\n  ["<Plug>(phenix-authenticate)"] = { "authenticate", "Phenix: authenticate provider" },\n''',
)
patch(
    "lua/phenix/mappings.lua",
    '''  ["<Plug>(phenix-refresh-callables)"] = { "refresh_callables", "Phenix: refresh callable catalog" },\n  ["<Plug>(phenix-cancel)"] = { "cancel", "Phenix: cancel current response" },\n''',
    '''  ["<Plug>(phenix-refresh-callables)"] = { "refresh_callables", "Phenix: refresh callable catalog" },\n  ["<Plug>(phenix-refresh-skills)"] = { "refresh_skills", "Phenix: refresh skill catalog" },\n  ["<Plug>(phenix-cancel)"] = { "cancel", "Phenix: cancel current response" },\n''',
)

# Package only the requested bundled skill and expose its root to conductor discovery.
patch(
    "modules/package.nix",
    '''      phenixRuntimeConfig = pkgs.writeText "phenix-runtime.json" (\n        builtins.toJSON (import ../config/phenix/runtime.nix)\n      );\n      neovim = inputs.neovim-nightly.packages.${system}.default;\n''',
    '''      phenixRuntimeConfig = pkgs.writeText "phenix-runtime.json" (\n        builtins.toJSON (import ../config/phenix/runtime.nix)\n      );\n      phenixBundledSkills = ../config/phenix/skills;\n      neovim = inputs.neovim-nightly.packages.${system}.default;\n''',
)
patch(
    "modules/package.nix",
    '''          PHENIX_CONDUCTOR_COMMAND = "${phenixConductor}/bin/phenix-conductor";\n        };\n''',
    '''          PHENIX_CONDUCTOR_COMMAND = "${phenixConductor}/bin/phenix-conductor";\n          PHENIX_SKILL_PATH = toString phenixBundledSkills;\n        };\n''',
)

# Deterministic conductor fixture mirrors the new protocol surface.
patch(
    "tests/fixture_conductor.py",
    '''ROUTING_PROFILES = [\n    {"id": "router.free", "providers": ["fixture"]},\n    {"id": "router.mixed", "providers": ["fixture", "fixture-two"]},\n]\n\n\ndef callable_descriptor''',
    '''ROUTING_PROFILES = [\n    {"id": "router.free", "providers": ["fixture"]},\n    {"id": "router.mixed", "providers": ["fixture", "fixture-two"]},\n]\nSKILLS = [\n    {\n        "id": "unslop",\n        "name": "unslop",\n        "description": "Cut AI tells from any writing. Must always apply.",\n        "invocation": "model_eligible",\n    }\n]\n\n\ndef callable_descriptor''',
)
patch(
    "tests/fixture_conductor.py",
    '''    if command_type == "get_callable_catalog":\n        reply(request_id, {"type": "callable_catalog", "callables": CALLABLES})\n        return\n\n    if command_type == "get_routing_catalog":\n''',
    '''    if command_type == "get_callable_catalog":\n        reply(request_id, {"type": "callable_catalog", "callables": CALLABLES})\n        return\n\n    if command_type == "get_skill_catalog":\n        reply(request_id, {"type": "skill_catalog", "skills": SKILLS})\n        return\n\n    if command_type == "get_routing_catalog":\n''',
)

# Smoke: public mappings, catalog loading, state projection and exact activation text.
patch(
    "tests/smoke.lua",
    '''  "<Plug>(phenix-select-model)",\n  "<Plug>(phenix-authenticate)",\n''',
    '''  "<Plug>(phenix-select-model)",\n  "<Plug>(phenix-select-skill)",\n  "<Plug>(phenix-authenticate)",\n  "<Plug>(phenix-refresh-skills)",\n''',
)
patch(
    "tests/smoke.lua",
    '''assert_true(not phenix.toggle_info(), "removed execution-tree info API unexpectedly remained active")\n\nassert_true(vim.bo[session.ui.transcript_buffer].filetype == "markdown", "transcript is not a markdown buffer")\n''',
    '''assert_true(not phenix.toggle_info(), "removed execution-tree info API unexpectedly remained active")\n\nassert_true(phenix.refresh_skills(), "skill catalog refresh was rejected")\nwait_for(function()\n  return #phenix.skills() == 1\nend, "skill catalog did not load")\nlocal skills = phenix.skills()\nassert_true(skills[1].id == "unslop", "unexpected bundled skill id")\nassert_true(skills[1].invocation == "model_eligible", "unslop was not model eligible")\nassert_true(session:state().skills[1].description:find("Cut AI tells", 1, true) ~= nil, "skill state lost its description")\n\nassert_true(vim.bo[session.ui.transcript_buffer].filetype == "markdown", "transcript is not a markdown buffer")\n''',
)
patch(
    "tests/smoke.lua",
    '''assert_true(transcript:find("echo: hello from neovim", 1, true) ~= nil, "assistant text was not rendered")\n\nassert_true(session:prompt("rich transcript"), "rich transcript prompt was rejected")\n''',
    '''assert_true(transcript:find("echo: hello from neovim", 1, true) ~= nil, "assistant text was not rendered")\n\nassert_true(session:prompt("/unslop rewrite this"), "explicit unslop prompt was rejected")\nwait_for(function()\n  return session:activity_state() == "settled" and has_entry(session, "assistant", "echo: /unslop rewrite this")\nend, "explicit unslop request did not reach the conductor unchanged")\n\nassert_true(session:prompt("rich transcript"), "rich transcript prompt was rejected")\n''',
)
