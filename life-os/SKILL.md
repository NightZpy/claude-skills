---
name: life-os
description: Create or daily-update a personal LIFE operating system — one offline-capable HTML artifact that is the registry/database of a person's WHOLE life (career, finances, health habits, family/relationships, learning, home/admin, personal projects, purpose), rendered as an interactive node graph + value/effort matrix + daily cockpit + second brain (inbox, distilled memory) + dated history + metrics. Domains are node groups; work is just one domain. Use when the user asks to create their life map/OS ("crea mi life os", "mapa de mi vida", "life dashboard") or to update it ("actualiza mi life os", daily refresh). Token rule — mechanical writes go through the CLI, LLM tokens only for judgment.
---

# Life OS — build & maintain a whole-life control system

One person = one hub folder = one living artifact. The artifact is a REGISTRY/DATABASE
of everything that happens in their life; LLM sessions update states and advice daily so
the person keeps moving toward THEIR stated goals. The HTML is generated — never
hand-edited. Life DOMAINS are node groups: carrera (a whole Employee OS can live here or
link out to a dedicated instance), finanzas, salud (logistics & habits ONLY — never
medical/therapeutic advice), familia/relaciones, aprendizaje, hogar/admin, proyectos
personales, propósito. Periods (quarters/years) are filters, never the scope.

**Engine & reference (bundled WITH this skill — self-contained, do not reinvent):**
- `template/` inside this skill's own directory: `engine/` (shell, builder, CLI, protocol),
  `seed/` (buildable placeholder instance + `lifeos-examples.json` — 11 FAKE nodes across
  the 8 domains with proposed group ids, plus example journal/inbox/memory/done_log/ritual
  entries) and `GUIDE-CLEAN.html` (the full didactic spec — architecture, DB schema
  key-by-key, CLI, pipeline; open it in a browser). Verify the template builds before
  seeding: copy engine/*+seed/* to a temp dir, rename seeds to q3-data.json/q3-prompt.txt,
  run `python3 build_q3.py`.
- The seed's PART 1 prompt documents every schema exactly — read it first, never guess
  formats. Everything is re-extractable from any generated HTML (RECOVERY property).
- NOTE: the engine's GROUPS map ships with work-group ids; a Life OS instance must extend
  it with the domain ids above (one color + sector per domain) — a small, one-time shell
  edit documented in lifeos-examples.json.

## Architecture (5 files, one hub folder — user picks the location, e.g. ~/lifeos/)

| File | Role | Who edits it |
|---|---|---|
| `q3-data.json` | THE database: nodes, edges, lenses, rituals, deadlines, focus, done_log, journal, inbox, memory, competencias/goals, calendar_events, tabs, meta | CLI for mechanical, LLM for judgment |
| `q3-prompt.txt` | Agent bootstrap: PART 1 generic system + PART 2 the person's profile | LLM (keep fresh every change) |
| `_q3-shell.tpl` | UI: graph, satellites, matrix, day-centered cockpit, second brain, search | Rarely; only UI features |
| `build_q3.py` | JSON + prompt + shell → self-contained offline HTML (+ computed metrics) | Almost never |
| `update_q3.py` | Mechanical CLI: `status · validate · build · touch · done · journal · note · memory-add · issue-state · add-issue · sync-linear · recover` | Run it, don't edit it |

Visual language (4 orthogonal channels): SHAPE = node type (● theme · ⬢ big bet ·
▢ tracked task · ◆ new topic · 👤 person · ◎ external · ★ personal) · COLOR = domain ·
RING = ownership · OPACITY = live vs done. Tasks/topics are SATELLITES orbiting their
theme. Days and any derivable view are VIRTUAL nodes (computed, never stored).

## Token economy (the core rule)

LLM tokens ONLY for judgment: node details, advice, focus picks, memory triage, custom
metrics. EVERYTHING mechanical goes through the CLI (auto-backup + rebuild + git-sync):

```bash
python3 update_q3.py note --text "call mom about the trip"     # zero-friction capture → inbox
python3 update_q3.py done --label .. --url .. [--guide (plain prose, NO UI text)] [--nav <node|ritual>]
python3 update_q3.py journal --node .. --text ..               # dated fact → bitácora
python3 update_q3.py memory-add --cat <personas|lecciones|decisiones|gotchas|preferencias> --text ..
python3 update_q3.py status | validate | build | touch | recover --from <html>
```

## The daily loop (Mode B — "actualiza mi Life OS")

1. `status`; then Layer 0 scripts (date bump; tracker sync if any).
2. Layer 1 sweep via cheap subagents over the person's sources — personal calendar,
   personal email, and whatever domain connectors exist; manual capture (`note`) covers
   80% before any connector. Refresh `calendar_events` (next 7 days, noise filtered).
   Findings PERSIST as journal facts.
3. Mechanical writes via CLI; SECOND BRAIN triage: inbox → journal (event) / memory
   (durable lesson about a person, money, habit) / pending (action) / sink. Weekly:
   consolidate memory (dedupe, stale, refresh the prompt's pinned index).
4. Judgment edits — MEMORY-FIRST: read memory before writing any advice/focus/plan
   ("mom hates surprises" shapes the visit plan like "the CTO wants numbers" shaped
   work docs). EDGE PROMOTION: a person/theme accumulating ≥2 journal facts about a
   node without an edge → add the edge, journal why.
5. Refresh prompt PART 2; rebuild; republish the artifact to its SAME url.

## Metrics — two kinds, never conflated (anti-vanity is product-defining)

- ELEMENTAL (universal, automatic, no LLM — computed at build): things completed per
  day/week/month/year, streaks as consecutive ISO periods (workouts, savings deposits,
  calls home), capture/triage volume, time dimensions where derivable.
- CUSTOM (goal-dependent, LLM-derived): at onboarding and each quarterly review, read
  the person's goals per domain and PROPOSE the few metrics that measure real progress
  (months of runway, trainings/week vs plan, visits/month); they approve; subjective
  ones live as self-scores vs their own rubric. Re-derive when goals change.
- HARD CAP: ~3-4 visible metrics per domain, each tied to a stated goal. Whole-life
  tracking slavery kills the habit — the dashboard answers "am I moving?" in seconds.

## Mode A — CREATE (new person)

1. Interview: life domains they want (start with 2-3, not all 8), goals per domain,
   the people that matter, recurring rituals, hard dates, sources they'll connect.
2. Copy engine from the template into a NEW hub folder; extend GROUPS with their domains.
3. Seed the DB guided by `lifeos-examples.json` (fake examples show each domain's shape);
   empty history/inbox/memory. Matrix = value-to-their-goals × effort.
4. Write their prompt PART 2 (profile, goals, sources, house rules); build; publish as a
   NEW artifact; save the URL into prompt + data.

## Non-negotiables

- Virtual-node doctrine: derivable = computed, primary = stored. Register once → surfaces
  everywhere (history, its node's 📜, day view, search). Search finds EVERYTHING, nodes
  first. Every affordance routes to the entity it names. Cadences are data, never
  hardcoded weekdays. Checked = shown; empty views offer a reset. No horizontal overflow.
  One shell writer at a time; concurrent CLI writes are safe.
- Commitments from any review/goal-setting become trackable objects: goal node (in the
  matrix) + ritual for the recurring part + deadline for the dated part + pinned memory.
- Privacy: the hub is local; back it up to a PRIVATE git repo (auto-commit on build);
  the published artifact is itself a versioned backup (recover regenerates sources).
  Health domain = logistics/habits only. Never leak one person's instance into another's.
