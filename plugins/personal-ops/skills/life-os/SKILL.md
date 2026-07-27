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
| `update_q3.py` | Mechanical CLI: `status · validate · build · touch · done · journal · note · memory-add · pending-done · issue-state · add-issue · sync-linear · recover` | Run it, don't edit it |

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
   MEETING PREP & DEBRIEF: every meeting of the day (any domain — work sync, doctor,
   school meeting) gets talking points in `meeting_prep` from memory (people notes),
   journal and pendings. Processing a finished conversation = OWNER-CENTERED fan-out
   triage: anchor first on what's directly the owner's (their words, commitments,
   mentions, their nodes), relate the rest through those anchors, skip the unrelated
   (search-first, never duplicate): commitments → pendings, new
   themes → nodes, details → journal, people insights → memory, topics for the next
   conversation → enriched prep, ambiguous → inbox. EXECUTION: imminent-meeting content
   goes to chat FIRST; ritual≡meeting content is written to BOTH the ritual draft and
   the day's prep; finish with a routing checklist + tell the owner where things render;
   denied sources → ask for link/paste in one message; tentative readings get flagged,
   never guessed silently.
   PENDING RE-TRIAGE (every loop): open pendings persist across days — re-manage them:
   valid → keep & feed today's suggestions · aged >3d → surface with age and ask (alive?
   schedule it? demote to inbox?) · EVIDENCE it's done (tracker closed, message sent,
   doc registered, owner said so) → retire via `pending-done --key <k> [--node --note]`
   · obsolete → same command, note says why. The UI checkbox is viewer-local
   (localStorage) — never a signal the agent reads nor the source of truth; the DB is.
   Pendings carry a created date; week boundary = full review.
5. RITUAL DRAFTS: generate the day's ready-to-paste updates into `drafts`
   {ritualId:{date,text}} for every communication ritual due — daily check-in every day (LIGHT: headline-level, no technical detail);
   meeting-bound rituals on the day their real meeting appears in the calendar (not a
   fixed weekday). From the DB + sweep — PRIMARY source = the owner's OWN sent messages
   that day (dedicated from:owner sweep); LANGUAGE = the destination's language (ritual
   `lang` or infer from the channel), never the owner↔agent chat language — owner's
   voice, with LINKS in the destination's
   native format (Slack: `name (raw URL)` — md [text](url) renders literally there;
   md contexts: [text](url)); never bare IDs; each renders inside its ritual with a copy button (recurring
   updates write themselves).
6. Refresh prompt PART 2; rebuild; republish the artifact to its SAME url.

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

## How to act (meta-principles — for situations no rule anticipated)

1. **Time-sensitivity triage first**: before processing/registering anything, ask "is
   there a deadline measured in minutes?" (an ongoing meeting, a message being awaited).
   If yes: deliver to the human FIRST, persist second.
2. **One write, all surfaces — then check the user's surface**: content belonging to an
   entity must be written at its source of truth and appear everywhere that entity
   renders; after writing, verify specifically the surface the user is most likely
   looking at (that's where "no lo veo" happens).
3. **Never "done" without "where"**: every registration ends by stating where each item
   now lives and renders.
4. **Blocked ≠ stuck**: a denied/missing path gets ALL fallback options in ONE message
   (link? paste? different source?), then stop. Never retry the blocked path.
5. **Uncertainty is flagged, never laundered**: low-quality sources (rough transcripts,
   ambiguous names) produce explicitly-tentative records plus a question — a guess must
   never be indistinguishable from a fact.
6. **Checklists beat memory**: multi-step protocols (debrief routing, loop steps) are
   walked item-by-item at the END — forgetting one row is the default failure mode, so
   the last step is always "which rows did I not consider?".
7. **"It's missing" → root-cause the pipeline, not the symptom**: when the owner reports
   something absent, find WHY the system missed it (source not covered? rule filtered
   it? never registered? anchor bug?) and fix the CLASS, then backfill the instance.
8. **A write without a read-back is a hope**: after every mutation (data, files, docs),
   verify with an independent check (grep/build/render). Silent no-op edits are a real
   and recurring failure mode.

## Micro-updates (scoped — the pattern between daily loops)
The full loop runs once a day. For everything else the owner names a SCOPE and the agent
processes only that slice (one cheap subagent + CLI writes + republish — a fraction of
the loop's cost): "update my OS with the meeting that just ended [name]" → find its
notes (Drive/Gemini/email), distill facts→journal, commitments→pendings, people
insights→memory, refresh affected drafts · "check my mentions since X" → targeted
search only · "process this doc/email" → that one source · "anota:"/"ya hice X" →
capture/state flip (near zero). Never run full sweeps for a scoped ask.
   SOURCE-SCOPED SYNC ("actualiza mi OS con lo nuevo de Slack/correo/Drive"): sweep that
   ONE source since its watermark (meta.<source>_synced), then run the FULL owner-centered
   routing table on the findings — create/relate nodes, edges, journal, memory, pendings,
   enriched preps, derived docs. MODEL TIERING MANDATORY: cheap subagents (Sonnet/Haiku)
   read the raw source in their own context and return distilled findings; CLI does the
   mechanical writes for free; only the routing/judgment pass runs on the top model, over
   distilled findings — never raw material on the expensive model.


## Non-negotiables

- Virtual-node doctrine: derivable = computed, primary = stored. Register once → surfaces
  everywhere (history, its node's 📜, day view, search). Search finds EVERYTHING, nodes
  first. Every affordance routes to the entity it names. Cadences are data, never
  hardcoded weekdays. Report specs are data too: stakeholder asks on a recurring
  report fold into its ritual template+guide the same day, so the next draft picks
  them up automatically; a recurring report's deliverable is ONE artifact republished
  each occurrence (same url, week-agnostic title) — versions are the archive. Checked = shown; empty views offer a reset. No horizontal overflow.
  One shell writer at a time; concurrent CLI writes are safe. Copy buttons: iframe
  clipboard often rejects — always textarea+execCommand fallback, never show success
  on a failed copy (on failure, select the text and ask for the manual shortcut).
- Commitments from any review/goal-setting become trackable objects: goal node (in the
  matrix) + ritual for the recurring part + deadline for the dated part + pinned memory.
- Privacy: the hub is local; back it up to a PRIVATE git repo (auto-commit on build);
  the published artifact is itself a versioned backup (recover regenerates sources).
  Health domain = logistics/habits only. Never leak one person's instance into another's.
