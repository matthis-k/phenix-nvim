# Skills

Phenix skills are conductor-owned procedural context. `phenix-nvim` does not parse `SKILL.md`, decide whether a skill should activate, or execute skill resources. It consumes the conductor's normalized skill catalog and submits ordinary user input.

## Frontend API

The native agent facade exposes:

- `Phenix.api.agent.skills()` to read the last validated skill catalog;
- `Phenix.api.agent.refresh_skills(callback)` to request `get_skill_catalog` from the conductor;
- `Phenix.api.agent.select_skill()` to pick a catalog entry and submit it explicitly as `/skill <id> <objective>`.

The corresponding public mappings are `<Plug>(phenix-select-skill)` and `<Plug>(phenix-refresh-skills)`.

Automatic/model-eligible activation remains a conductor/model concern. Slash-prefixed input such as `/unslop ...` is not interpreted by Neovim; it is forwarded unchanged to the conductor.

## Bundled skills

The wrapped Phenix editor currently bundles exactly one skill: `unslop`, mirrored from Lauren Tan's pstack plugin. The packaged wrapper exposes `config/phenix/skills` through `PHENIX_SKILL_PATH`, so the conductor can discover the bundled `SKILL.md` alongside normal user/project skill roots.

No other pstack skills are bundled at this time. The mirrored skill retains its upstream MIT license and source attribution under `config/phenix/skills`.
