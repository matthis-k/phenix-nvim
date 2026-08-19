from pathlib import Path

path = Path("tests/startup.lua")
text = path.read_text()
old = '''assert(type(default_catalog.models) == "table" and #default_catalog.models > 0, "Phenix backend exposed no default model target")\n\nlocal auth_methods = {}\n'''
new = '''assert(type(default_catalog.models) == "table" and #default_catalog.models > 0, "Phenix backend exposed no default model target")\n\nlocal packaged_skill_refresh_done = false\nlocal packaged_skill_refresh_error = nil\nassert(\n  phenix.refresh_skills(function(_, err)\n    packaged_skill_refresh_error = err\n    packaged_skill_refresh_done = true\n  end),\n  "packaged skill catalog refresh was rejected"\n)\nassert(\n  vim.wait(5000, function()\n    return packaged_skill_refresh_done\n  end, 20),\n  "packaged conductor did not return its skill catalog"\n)\nassert(packaged_skill_refresh_error == nil, "packaged skill catalog refresh failed: " .. vim.inspect(packaged_skill_refresh_error))\nlocal packaged_skills = phenix.skills()\nassert(#packaged_skills == 1, "packaged conductor exposed an unexpected number of bundled skills")\nassert(packaged_skills[1].id == "unslop", "packaged conductor did not discover the bundled unslop skill")\nassert(packaged_skills[1].name == "unslop", "packaged unslop skill lost its canonical name")\nassert(packaged_skills[1].invocation == "model_eligible", "packaged unslop skill is not model eligible")\nassert(\n  packaged_skills[1].description:find("Cut AI tells", 1, true) ~= nil,\n  "packaged unslop skill lost its upstream description"\n)\n\nlocal auth_methods = {}\n'''
if text.count(old) != 1:
    raise SystemExit(f"expected one packaged catalog anchor, found {text.count(old)}")
text = text.replace(old, new, 1)
old = '''  "refresh_callables",\n  "callables",\n  "run_callable",\n  "select_callable",\n'''
new = '''  "refresh_callables",\n  "callables",\n  "refresh_skills",\n  "skills",\n  "run_callable",\n  "select_callable",\n  "select_skill",\n'''
if text.count(old) != 1:
    raise SystemExit(f"expected one semantic action anchor, found {text.count(old)}")
text = text.replace(old, new, 1)
old = '''  "<Plug>(phenix-select-callable)",\n  "<Plug>(phenix-refresh-callables)",\n}) do\n'''
new = '''  "<Plug>(phenix-select-callable)",\n  "<Plug>(phenix-refresh-callables)",\n  "<Plug>(phenix-select-skill)",\n  "<Plug>(phenix-refresh-skills)",\n}) do\n'''
if text.count(old) != 1:
    raise SystemExit(f"expected one public mapping anchor, found {text.count(old)}")
path.write_text(text.replace(old, new, 1))
