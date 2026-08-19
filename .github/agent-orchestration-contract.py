from pathlib import Path

path = Path("config/phenix/runtime.nix")
content = path.read_text()

old = 'descriptor = descriptor "workflow" id title;'
if content.count(old) != 1:
    raise RuntimeError(f"expected one orchestration descriptor legacy kind, found {content.count(old)}")
content = content.replace(old, 'descriptor = descriptor "orchestration" id title;', 1)

legacy_ids = content.count('"workflow.')
if legacy_ids == 0:
    raise RuntimeError("expected legacy workflow.* orchestration IDs")
content = content.replace('"workflow.', '"orchestration.')

old_efforts = '''  allowedEfforts = [
    "low"
    "medium"
    "high"
  ];
  target =
    provider: model: effort:
    assert builtins.elem effort allowedEfforts;
    {
'''
new_efforts = '''  target = provider: model: effort: {
'''
if content.count(old_efforts) != 1:
    raise RuntimeError("frontend inference-effort allowlist shape changed")
content = content.replace(old_efforts, new_efforts, 1)

path.write_text(content)
