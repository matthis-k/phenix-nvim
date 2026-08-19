# Skills

Phenix skills are conductor-owned procedural context. `phenix-nvim` does not parse `SKILL.md`, decide whether a skill should activate, or execute skill resources. It consumes the conductor's normalized skill catalog and submits ordinary user input.

## Frontend API

The native agent facade exposes:

- `Phenix.api.agent.skills()` to read the last validated skill catalog;
- `Phenix.api.agent.refresh_skills(callback)` to request `get_skill_catalog` from the conductor;
- `Phenix.api.agent.select_skill()` to pick a catalog entry and submit it explicitly as `/skill <id> <objective>`.

The corresponding public mappings are `<Plug>(phenix-select-skill)` and `<Plug>(phenix-refresh-skills)`.

Automatic/model-eligible activation remains a conductor/model concern. Slash-prefixed input such as `/write ...` is not interpreted by Neovim; it is forwarded unchanged to the conductor.

## Bundled skills

The wrapped Phenix editor currently bundles exactly one skill: `write`, which consolidates unslop and writing-for-agents into a single skill with three audience modes. The packaged wrapper exposes `config/phenix/skills` through `PHENIX_SKILL_PATH`, so the conductor can discover the bundled `SKILL.md` alongside normal user/project skill roots.

The `write` skill is marked "must always apply" so the model activates it for every output. It covers AI-tell removal (formerly unslop) and structured document design for agent audiences (formerly writing-for-agents) in one place.

Two additional skills support decision-making workflows:

- **grilling** applies a structured interview protocol to stress-test plans, decisions, or ideas before acting. It maps the conversation as a design tree and works through decisions in rounds, asking only the frontier questions that are unblocked by settled prerequisites. The protocol separates fact-finding from decision-making and ensures every branch is visited before action.

- **to-questionnaire** converts an unanswered decision into a structured questionnaire for another person. It interviews the user about the send rather than the subject, then generates a Markdown document targeting the gap between what the user needs and what the recipient knows. The template enforces most-important-first ordering and async-friendly structure.

All three skills are pure skills, not orchestrations. They inform the protocol and methodology, while orchestrations handle multi-agent execution.
