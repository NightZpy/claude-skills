---
name: employee-os
description: Create or daily-update a personal "employee operating system" — an offline-capable HTML artifact with an interactive node graph (themes, bets, Linear issues, allies, external actors), a value/complexity matrix, a daily cockpit, rituals, stakeholder playbook, KPIs and a durable dated history (done_log + journal). Works for ANY employee at ANY company. Use when the user asks to create their work map / employee dashboard ("crea mi mapa de trabajo", "employee OS", "dashboard personal de trabajo") or to update an existing one ("actualiza mi mapa", daily refresh). Token rule — mechanical writes go through update_q3.py, LLM tokens only for judgment fields.
---

# Employee OS — build & maintain a personal work-control system

One employee = one hub folder = one living artifact. The artifact is a REGISTRY/DATABASE
of everything that happens in their work life; LLM sessions update states and advice so
the employee keeps improving at their company. The HTML is generated — never hand-edited.
Scope = the WHOLE tenure, not one quarter: periods are node fields (`period:"h1"|"q3"`,
filterable in the UI), past delivered workstreams live as `group:"shipped"` + `state:"done"`
nodes (dimmed, feeds-edges into current work) and double as performance-review evidence.
When a performance review produces COMMITMENTS, register them as trackable objects: a
goal node (group mine, in the matrix) + a ritual for the recurring part + a deadline for
the dated goal + a pinned memory note — never just prose.

**Reference instance (canonical example of every file):**
`<the reference hub folder>` — q3-data.json,
q3-prompt.txt, _q3-shell.tpl, build_q3.py, update_q3.py, q3-map-2026.html, design-docs/.
Also a PRIVATE git repo: [YOUR-PRIVATE-BACKUP-REPO] (auto-commit+push on
every build = the versioned off-machine backup; plus README.md with the system docs).
The embedded prompt (q3-prompt.txt, PART 1) documents every schema exactly — read it
first; do not guess formats. Everything is also re-extractable from the generated HTML
(consts hold the data verbatim; `<pre id="promptText">` holds the prompt).

## The architecture (5 files, one folder)

| File | Role | Who edits it |
|---|---|---|
| `q3-data.json` | THE database: nodes, edges, lenses, rituals, deadlines, focus, evidence, done_log, journal, tabs HTML, meta | CLI for mechanical, LLM for judgment |
| `q3-prompt.txt` | Agent bootstrap: PART 1 generic system + PART 2 employee profile; injected into the artifact | LLM (keep fresh every change) |
| `_q3-shell.tpl` | UI: CSS + runtime JS (graph, satellites, shapes, lenses, filters, toolbar, tabs, cockpit) | Rarely; only for UI features |
| `build_q3.py` | JSON + prompt + shell → self-contained offline HTML | Almost never |
| `update_q3.py` | Mechanical CLI: `touch · done · journal · issue-state · add-issue · build · status` | Run it, don't edit it |

Visual encoding (4 orthogonal channels): SHAPE = node type (● theme · ⬢ strategic bet ·
▢ Linear issue · ◆ new topic · 👤 ally · ◎ external · ★ personal) · COLOR = area/group ·
RING = ownership (gold = the employee's, dashed grey = teammates') · OPACITY = live vs done.
Issues/topics are SATELLITES orbiting their parent theme node.

## Token economy (the core rule)

LLM tokens ONLY for judgment: node detail/entry texts, ritual advice, insights, narrativa,
focus picks, stakeholder plays. EVERYTHING mechanical goes through the CLI (each mutating
command bumps meta.updated and rebuilds):

```bash
python3 update_q3.py status                                   # where things stand
python3 update_q3.py validate                                 # schema check of the JSON DB
python3 update_q3.py touch [--date YYYY-MM-DD]                # daily date bump + rebuild
python3 update_q3.py sync-linear [--dry-run]                  # auto-sync issue states from Linear (LINEAR_API_KEY)
python3 update_q3.py done --label .. --url .. [--guide ..] [--nav <node|ritual>]  # deliverable → history
python3 update_q3.py journal --node .. --text ..              # append event to the bitácora
python3 update_q3.py issue-state --id AG-#### --state done    # flip an issue satellite
python3 update_q3.py add-issue --id AG-#### --parent <theme> --sub .. [--owner mine|other]
python3 update_q3.py recover --from <map.html> [--out DIR]    # regenerate the JSON+prompt from any
                                                              # published HTML (pure code, no LLM)
python3 update_q3.py note --text ".."                         # SECOND BRAIN: zero-friction capture → inbox
python3 update_q3.py memory-add --cat <personas|lecciones|decisiones|gotchas|preferencias> \
    --text ".." [--refs node1,node2] [--pin]                  # distilled durable note → memory
```

Every mutation auto-backs-up the DB first (`.backups/`, last 20 kept). The DB is JSON by
decision (not SQLite): the build embeds JSON anyway, LLM judgment edits are plain-text,
and the file is diffable + re-extractable from the generated HTML; growth is handled by
quarterly rollover. The update pipeline has 3 layers — Layer 0: pure scripts, zero tokens
(touch, sync-linear; cron-able) · Layer 1: cheap subagents sweep Slack/Docs/tracker
comments and return distilled node-mapped findings · Layer 2: the session model applies
judgment (journal/done_log via CLI, state/advice edits, prompt refresh, republish).

The Hoy tab's "today" is anchored to `meta.updated` (the stored build date), NOT the live
clock — every published artifact version reflects its own day and history stays stable.

## Mode A — CREATE (new employee / new company)

1. Ask for (or gather): who they are, role & trajectory goal, team, hard dates, planning
   sources (roadmap docs/sheets, issue tracker, Slack channels), allies/stakeholders, KPIs.
2. Copy `_q3-shell.tpl`, `build_q3.py`, `update_q3.py` from the reference instance into a
   NEW hub folder (docs tree, never inside a code repo). Do not modify them.
3. Seed `q3-data.json` following the schemas in the reference prompt's PART 1: theme nodes
   from their planning sources, edges (dep/feeds/risk/val/own), issue satellites from their
   tracker, ally nodes, lenses, rituals with role-oriented advice, deadlines, templates,
   tabs HTML. Empty done_log and journal. Matrix axes = value-to-them × complexity.
4. Write their `q3-prompt.txt`: copy PART 1 verbatim (system is identical), rewrite PART 2
   (profile, sources, KPIs, house rules).
5. `python3 build_q3.py` → publish the HTML as a NEW artifact; save the URL into the
   prompt and data (Fuentes). Regenerate the docs index if a docs tree with indexer exists.

## Mode B — UPDATE (the daily loop)

1. `python3 update_q3.py status`.
2. Gather fresh context from the profile's sources (Slack, email, Linear/tracker, docs,
   calendar) — use cheap subagents for the sweep; only distilled findings reach the main
   context, and they are PERSISTED as journal facts.
3. Mechanical writes via the CLI: journal events, done_log entries (with --guide/--nav),
   issue state flips, new issue satellites.
4. SECOND BRAIN triage (daily): read the inbox top-down — each item → journal (event),
   memory-add (durable lesson/insight), week_pendings (action), or let it sink. Weekly
   (with the health-note ritual): consolidate memory — dedupe/merge (bump date_upd), flag
   stale, cross-ref to nodes, refresh the pinned index in the prompt's PART 2. Never
   delete; merge or mark. Hygiene is scheduled work, not emergent (Anthropic's lesson).
   MEMORY-FIRST: every judgment output (advice, insights, focus, drafts, meeting prep)
   must be generated AFTER reading memory.cats and applying the relevant notes — memory
   that isn't consulted is dead weight.
5. Judgment edits in `q3-data.json` — only what genuinely changed: node statuses/details,
   focus, week_pendings, ritual advice, insights, evidence lines (KPI log). Quarterly (and
   before every performance review): refresh `competencias` (self-score 1-5 vs the official
   rubric). Performance metrics stay FEW and fundamental — 3 computed at build time from
   the DB (deliveries/month, health-note streak, incidents logged) + the competency
   self-score; never add vanity metrics.
6. Keep `q3-prompt.txt` PART 2 in sync (new context in, stale out; bump refresh date) —
   the prompt and this SKILL are updated on EVERY pass that changes system behavior.
7. Republish the artifact FROM the generated HTML to the SAME url (the `url` param).
   Every publish = a version = a daily snapshot; the in-doc history (done_log + journal +
   inbox + memory) is the queryable record.

## Rules

- Never hand-edit the generated HTML; never bypass the CLI for mechanical writes.
- Surgical judgment edits: touch only fields that changed; history is append-only.
- Private ideas stay in the personal instance only — never leak them into shareable
  versions (a company-shareable variant strips the personal layer).
- Complex tasks get a standalone design-doc artifact (problem + up to 3 options) linked
  from their node, not inlined in the map.
- After any UI (shell) change: rebuild and verify headless (zero console errors) before
  publishing; after any docs change: regenerate the docs index.
