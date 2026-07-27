# Employee OS — Template

Clean, instantiable copy of the engine + a minimal seed. To create a NEW instance
(any person, any company — or a Life OS with life domains as groups):

1. Copy `engine/*` and `seed/*` into a new folder:
   `cp engine/* seed/* /path/to/new-instance/`
2. Rename seeds: `mv data.template.json q3-data.json && mv prompt.template.txt q3-prompt.txt`
3. Seed the data (interview the owner or run the `employee-os` skill in CREATE mode):
   replace example nodes/edges/rituals/tabs with their real world; rewrite prompt PART 2.
4. `python3 build_q3.py` → open `q3-map-2026.html`. Publish as an artifact or host it.
5. Daily: run the loop (SKILL.md Mode B). Mechanical writes via `update_q3.py` only.

The engine files here are canonical copies from the live instance at the repo root —
if root evolves, refresh them (`cp ../_q3-shell.tpl ../build_q3.py ../update_q3.py ../SKILL.md engine/`).
