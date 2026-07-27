# Replication prompt v3 — field-tested (greenfield, existing codebases, AND a thin service client)

> Paste everything below this line to a coding agent inside the target repo, together with
> this kit (`SKILL.md` + `scripts/`) for Modes A/B — Mode S (§12) needs neither. This v3
> supersedes the original web-stack prompt for practical use: it works for a brand-new project
> born with this philosophy, a large pre-existing codebase, AND as a thin client of a
> separate behavior-review service (§12 — never replacing the first two, see §0); it
> carries every lesson from a real replication into the hardest case (a VS Code
> fork / Electron desktop app).

---

You are installing the **behavior-report review system** in this repository: the product
owner never clicks through the app or watches terminals — they review every feature
through ONE self-contained HTML report (captioned screenshots + GIFs of real E2E behavior
stories) published as a Claude Artifact at a permanent URL, backed by a `features.json`
BDD contract, hard quality gates, and a never-regress ratchet.

Base spec: read the kit's `SKILL.md` (stage contracts §2, tool swap table §3, spec §5,
generator §6, story rules §7, publish workflow + hard rules §8, mutation playbook §9) and
use the kit's `scripts/` as the reference implementation. Everything below AMENDS that
spec with field-tested rules. Where they conflict, this document wins.

## 0. First decision: which mode is this repo?

**Mode A — greenfield** (new project, born with the philosophy):
- Every gate is HARD from the first commit: there is no pre-existing debt to stage around.
  100% coverage/mutation on day one is trivial when the codebase is one feature big — and
  it never gets easier than today.
- `features.json` starts with the FIRST real feature (spec before code, from the very first
  request). The demo feature required by the definition-of-done is simply feature #1.
- Skip §2's staging machinery conceptually, but still create the `GATES_ON` array — set it
  full from day one. It documents which gates exist and keeps the scripts identical across
  both modes (one less fork of the kit to maintain).
- Scope = the whole repo (still write the scope file; it future-proofs vendored code).

**Mode B — existing codebase** (retrofit):
- Follow §2 (staged gates) and §3 (scope) strictly — they are the biggest deltas vs. the
  original prompt, learned the hard way.
- The burn-down (§4) is your adoption path: the report starts as an honest audit of how
  much of the existing app is actually proven.

**Mode S — service client (thin)** (a behavior-review service implementing
`docs/INGEST-CONTRACT.md` is reachable: URL + API key with the review scope + its MCP
server configured):
- See §12 for the full flow — it replaces the pipeline/generator side of the kit only,
  never the doctrine (capture rules, spec discipline, honest red).
- This is never the only path: whenever no such service exists or is reachable, fall back
  to Mode A or B above — this kit never becomes service-only.

Everything else (§1, §5–§10) applies identically to Modes A and B; Mode S is self-contained
in §12 and cross-references `SKILL.md` directly instead.

## 1. The two-artifact split (both modes — do this first)

Keep the kit generic; the project-custom version lives IN the target repo, never in the kit:

- Pipeline scripts → the repo's scripts dir (e.g. `scripts/report/*.sh`), re-bodied for the
  stack but keeping the kit's stage contracts (the JSON files each stage writes + exit
  semantics — that is the portable core; leaf bodies are disposable).
- One `*-scope.sh` file defining the project scope + `GATES_ON` — sourced by every stage.
  Comment constraint: those path variables get interpolated into inline `node -e` scripts —
  keep them repo-relative, no spaces/quotes.
- Stories + generator + state files → `test/behavior/` (or the repo's e2e home).
- A decision record (`docs/BEHAVIOR-REPORT-PLAN.md`-style): driver decision, stage mapping
  table (kit → this repo), scope, rollout, known machine issues. Update it in the same
  branch as any change.
- The operating skill for future agents → **check where tracked agent skills live**:
  `.claude/` is often gitignored; the tracked path may be `.agents/skills/` (it was in
  the desktop-app replication). Put the skill at the tracked path (copy/link to `.claude/` if useful).
- Track the work as a repo issue; branch per the repo's rules; never commit without asking.

## 2. Mode B only — staged gates

Turning every 100% gate on over a pre-existing codebase makes the pipeline permanently red
on day 1 — which trains everyone to ignore red. That is worse than no gate.

- `GATES_ON=(...)` in the scope file. A stage in the list is HARD (nonzero exit fails the
  pipeline). A stage NOT in the list still RUNS best-effort and prints an honest
  `PENDING (staged — #<issue>)` line with real counts (e.g. "36 raw-hex violations",
  "10 high npm audit findings, upstream deps") — never a fake pass, never silence.
- **Staged ≠ lowered.** The sacred rule ("never lower an accepted gate") is untouched: a
  staged gate was never on. Turn gates on ONE at a time (tokens/hygiene → coverage →
  mutation), each only when it runs green; the ratchet guards from the first accepted row.
- Realistic day-1 hard set for a mature repo: the repo's OWN existing checks (type-check,
  layering, lint/hygiene, pre-commit) — call them, don't duplicate them — plus gitleaks,
  plus the e2e stories stage. Everything else starts PENDING.

## 3. Mode B only — scope

In a fork/monorepo, every 100% gate applies ONLY to project-authored code
(`APP_SCOPE=("src/vs/<app>")`-style). Running knip/jscpd/coverage over upstream or
vendored code drowns in noise and is unpayable. One scope file, sourced by all stages;
mirror the globs manually into stryker/knip configs (configs can't source bash) with a
sync-reminder comment. Derive the scope honestly (commit history, the project's own dirs) —
never guess it.

## 4. Mode B only — the burn-down (adoption path for existing apps)

Inventory the EXISTING features as `proposed` behaviors in `features.json` → they render as
red NO STORY cards → the report becomes an honest scoreboard of how much of the app is
proven → story them one by one (failures found are real bugs), one report version per
round. Propose the inventory to the owner as a compact list BEFORE writing stories. In Mode
A this section is moot: the spec grows feature by feature from day one and there is never a
NO STORY backlog.

### The inventory MUST be multi-pass (field lesson: one pass found 8 of 18 features)

A single code-reading pass systematically undersells a real product — in the desktop-app replication it missed
almost HALF the shipped surface (quick-ask window, voice input, background tasks, artifact
versioning, the result renderers, OS notifications, inline document editing, mid-turn
redirect, two whole dashboard screens). Run the inventory as independent passes with
DIFFERENT evidence sources, and don't stop until a pass finds nothing new (loop-until-dry):

1. **Code + docs pass** — the main UI tree and product docs. Produces the first draft.
   Expect it to be incomplete; never present it as final.
2. **Completeness critic** — a FRESH agent whose only job is to find what pass 1 missed,
   pointed at the places first passes under-cover: secondary entry points (preload scripts,
   second windows, tray/global shortcuts, deep-link/protocol handlers, OS notifications),
   the main-process (not just renderer) code, result/renderer components (what "the result"
   actually looks like per type), and issue numbers referenced in code comments.
3. **Archaeology + live walkthrough** — (a) ALL issue-tracker issues including CLOSED ones
   (every shipped feature usually has one — the richest single source), (b) full
   feature-commit history and any changelog, (c) actually RUN the app and walk every tab,
   menu, and dropdown, screenshotting each surface and comparing what you SEE against the
   list. The live pass both finds gaps and CONTRADICTS wrong claims (a "feature" that
   isn't reachable, a "blocked" that's actually testable).
4. **Wiring check** — inventory the app's capabilities (connectors, tools, skills) and
   check whether shipped features actually USE them. In that replication every connector existed
   but the skills never called them — a gap class that capability-shaped audits miss
   entirely. These wiring gaps are the cheapest, highest-leverage items on the roadmap.

Also verify TESTABILITY claims adversarially: a pass declared a whole feature "untestable
offline" when two of its states were reachable by simple config. Before marking anything
blocked, ask "what config/env/seed would make this deterministic?" — and record what
unblocks the rest as a harness issue, not as silence.

### Judge existing features against the quality bar — proving it runs isn't enough (field lesson)

Covering an ALREADY-BUILT feature is a different job from building a new one: a passing
story only proves the app does what the story asserts — it says nothing about whether the
feature is good enough. Judge it against the product's quality bar too, and route what you
find through the right channel:

1. **A story that fails = a real bug.** It stays honestly red until fixed — never deleted
   or watered down to force green.
2. **A rough edge or missing affordance** (not a broken assertion — a quality gap) = a NEW
   `proposed` behavior in `features.json` PLUS an issue in the repo's tracker, prioritized
   like any other roadmap item.
3. **Quality below the bar with no crisp behavior to encode** (e.g. hallucinated or
   placeholder UI) = file a tracker issue with the evidence (screenshot/transcript) even
   without a story — not everything worth flagging fits the spec's behavior-sentence shape.

Skip this triage and the burn-down degenerates into a coverage-checkbox exercise: a passing
story over a mediocre existing feature "proves" it and silently drops the improvement the
owner actually wanted surfaced.

## 5. App-type appendix: desktop / Electron (replaces the web-stack assumptions)

Skip if your app is a plain web stack — the kit's reference scripts already cover it.

- **Driver: Playwright `_electron.launch`**, not a hand-rolled CDP driver. You need
  auto-waiting locators + `expect` + native `recordVideo`; hand-rolling that over raw CDP
  is reinventing Playwright badly. In a VS Code fork the proven in-tree precedent is
  `test/automation/src/playwrightElectron.ts`. Keep any existing CDP dev tool for
  interactive self-verify — different job, no overlap. Fallback if `_electron` fights the
  app's boot: `connectOverCDP` against the repo's own debug launcher + CDP screencast
  frames for GIFs.
- **Launch recipe: mirror the repo's own dev launcher EXACTLY** — read its launch script
  and copy binary path derivation (from product config, never hardcoded), args, and env
  vars. Find the app's offline/deterministic story (mock/offline env flags) so stories need
  no API keys and no network.
- **Isolation analog** of docker-compose+tmpfs: a throwaway user-data dir (`mkdtempSync`)
  per TEST, removed on teardown. Edge stories can pre-seed it (leftover files from an
  "interrupted session" = a cheap, honest corruption scenario).
- `_electron.launch({ timeout: 0 })` and govern via the test timeout (Electron apps boot
  slowly; 120s is realistic for a first boot).
- **Video mechanics** (custom launches don't auto-attach video): grab `page.video()`
  BEFORE `app.close()`; `await video.path()` AFTER close (close finalizes the webm); then
  `testInfo.attach('video', ...)` yourself.
- **Fixture leak guard**: wrap the pre-`use` setup (firstWindow, console hookup) in
  try/catch → on error `app.close().catch(()=>{})`, remove the udd, rethrow. Playwright
  only runs teardown for code after `await use()`; a hung boot otherwise leaks the process.
- Follow the app's REAL first-run flow: the main surface may be behind an onboarding screen
  (one app had a first-run space-creation welcome). Discover the DOM live and write
  captions from what actually renders — never from what you assumed.

## 6. Playwright → generator gotchas (results.json truths, any app type)

- Tags: `{ tag: ['@edge'] }` goes as the SECOND argument of `test(title, opts, fn)` — in
  the third position it's silently ignored. In results.json the `@` is STRIPPED: match
  `tags.includes('edge')`.
- Specs sit at multiple nesting depths — walk `suites[]` recursively; a suite whose title
  matches a `features.json` key sets the feature context for everything beneath (nested
  non-feature describes don't reset it).
- Captions travel as attachment names: `snap()` attaches `snap:<caption>` — the prefix
  survives the JSON reporter; attachment paths are absolute.
- Seeds via `testInfo.annotations` `{ type: 'seed' }`; texts must be RUN-STABLE (no
  timestamps/ids) or hashes churn and stories re-flag NEW/CHANGED every run.
- Duplicate story keys (same feature + title): a plain Map silently drops one — warn on
  duplicates in the generator.
- Escape EVERY user-origin string in the generated HTML (titles, captions, seeds, errors,
  askedFor) with an `esc()` covering `& < > "` and keep all attributes double-quoted — the
  HTML gets published; treat it as a public page.
- Aim for byte-stable output on identical inputs (except the timestamp) — the GIF encode is
  deterministic; this makes CHANGED badges trustworthy.

## 7. Pipeline script gotchas (bash, any app type)

- `npm audit --audit-level=high` exits 1 on findings — under `set -e` a naive pipe crashes
  the pipeline. Wrap stages in `set +e` / capture exit / `set -e` and decide via `gate_on`.
- A test runner filtered by grep may exit 0 with ZERO matched tests — parse the
  "N passing" count; 0 matches on a hard gate is a false-green.
- Prefer the system's ffmpeg over an npm `ffmpeg-static` dep when present — but the machine
  ffmpeg can be BROKEN (homebrew lib-version mismatch after a partial upgrade → dyld
  abort). The generator must degrade honestly (a visible "no GIF: ffmpeg unavailable" note
  per story) — never bake machine-specific `DYLD_*` workarounds into shipped code; put the
  repair (`brew reinstall ffmpeg`) in the skill's troubleshooting table.
- Wire ONE entry point in the repo's runner (`./run.sh report`, `make report`) — but know
  what the wrapper adds (Node-version checks etc.); document the direct generator call for
  `--accept` as the equivalent.
- Testing `--accept` without polluting state: back up `features.json`, accept, verify the
  round-trip (zero NEW/CHANGED, media replaced by references, exactly 1 history row),
  restore the backup and delete the state files. **The real first accept belongs to the
  owner after reviewing** — the repo must land un-accepted.

## 8. Publishing mechanics (Claude Artifacts, verified 2026-07)

- The capability is BUILT INTO Claude Code CLI — no plugin, no separate tool to install.
  Gate: session authenticated via claude.ai login (Pro/Max/Team/Enterprise); API-key
  sessions can't publish. If the tool isn't exposed in the current session, a fresh session
  usually has it. Publishing happens by asking (or calling the Artifact tool when exposed).
- The published file is CONTENT-ONLY: strip only the skeleton TAGS
  (`<!doctype>/<html>/<head>/<body>`) — KEEP `<title>`, the inline `<style>`/`<script>`,
  AND the `<meta name="viewport">` (field lesson: stripping all metas ships a page that
  phones render at desktop width, shrunken and unreadable — the artifact skeleton does not
  add a viewport for you; your media queries only work if the viewport meta survives).
- Strict CSP: zero external requests (CDN/fonts/images/scripts). Everything inline; media
  as data-URIs. `<a href>` links out are fine.
- ~16 MiB cap confirmed; media scoping (only NEW/CHANGED/failing/proposed embed) is what
  keeps you under it forever.
- FIRST publish mints the permanent URL → immediately PIN it in the operating skill (§5
  publish step, with "pass `url:` from new sessions or you mint a new artifact") and in the
  decision record. One URL, one favicon, a short label per version.
- The report is one artifact; if the owner needs a "how does this system work" explainer,
  that's a SEPARATE artifact with its own URL/favicon — never mixed into the report's.

## 9. Review integration (three layers, don't conflate them)

The pipeline has NO LLM reviewer of its own — jscpd/knip/tsc are deterministic mechanics,
not judgment. Slot the project's existing code-review rule (Codex/Claude/whatever, with its
fallback chain) as an explicit step BEFORE publishing, so the artifact always shows
post-review code. The stack:
1. Deterministic gates (mechanical, non-negotiable) →
2. LLM judgment review of the diff (logic, design, security) →
3. The owner's product review via the artifact (the only human step, the final word).
Write this ordering into the operating skill's flow.

## 10. Owner experience (what made adoption work)

- Report prose/captions in the OWNER'S language (kit §7's actual rule is language-neutral —
  "the language the product owner reviews in," no English default — but the installer must
  still set it explicitly for this repo's owner).
- The metrics dashboard renders "—" for staged/missing metrics — an honest dashboard full
  of dashes beats an invented number; cards wake up as gates turn on, sparklines appear
  after ≥2 accepted rows. (Mode A: cards are live from day one; you skip this caveat.)
- Expect the owner to ask "is this right?" at the first dashboard with zeros/dashes —
  pre-empt it: zeros and dashes ARE the staged-rollout truth; say so in chat when publishing.
- Consider a one-time explainer artifact (lifecycle animation, badge glossary, gate layers,
  mutation-in-plain-words, the ratchet) — understanding the system is part of the system.

## 11. Build order that worked (for the executing agent)

1. Stories first — fixtures + the demo feature (happy + `@edge`) against the REAL app,
   iterating live until green, with visual self-verification (read a snap, confirm it shows
   the real surface, not a blank window). Mode A: the demo feature is your product's
   feature #1.
2. Pipeline scripts in parallel (disjoint files): scope + `GATES_ON` + full-report +
   static-checks calling the repo's own gates + runtime preflight in e2e-tests.
3. Generator AFTER stories (it needs the real results.json shape).
4. Operating skill + decision record AFTER the generator (document reality, not intent).
5. One full end-to-end run of the single entry point.
6. LLM code review of the whole diff (with fallback chain if the primary reviewer is
   down) → triage → fix → re-verify.
7. Publish v1 → pin URL → owner reviews → `--accept` → ask before committing.

**Definition of done** — same as the kit (demo feature green end-to-end, all report
sections with correct badges + legend, `--accept` round-trips clean, operating skill lets a
fresh agent run everything without this prompt) PLUS: `GATES_ON` explicit (full in Mode A;
honestly staged with real PENDING counts in Mode B), scope file filled from the real
project-authored tree, artifact URL pinned, and the repo left in the state the owner
accepted.

---

## 12. Mode S — service client (thin)

**When to use it**: a behavior-review service implementing `docs/INGEST-CONTRACT.md` is
reachable — a URL, an API key scoped for review, and its MCP server configured in this
session. Modes A and B (§0) are NOT superseded: whenever no such service exists, or it's
unreachable, fall back to the classic replication above — this kit never becomes
service-only. Mode S replaces only the pipeline/generator side of the kit; every doctrine
rule below still applies in full.

### What this repo installs (and what it doesn't)

Nothing from §1's two-artifact split lands here: no `scripts/report/*`, no
`build-review-report.mjs`, no ffmpeg, no accept script, no HTML assembly. The ~2,000-line
generator and every pipeline stage that used to get re-bodied per stack now live once,
server-side (`SERVICE-DESIGN.md` §1–§2) — that's the entire point of "thin." Install only:

- **`features.json`** — unchanged shape and rules (`SKILL.md` §5): `askedFor` a faithful
  paraphrase, behaviors `proposed → approved`, 1–4 terse `done` conditions, story titles
  joining to behavior titles by EXACT string match. The service reads it verbatim
  (`INGEST-CONTRACT.md` §1.1) — never redesigned, never partial.
- **E2E stories carrying the FULL capture doctrine**, `SKILL.md` §7 unchanged: paced
  actions (slowMo ~400–500ms at record time — playback speed cannot fix a state skipped on
  camera), decode/paint gates before every screenshot, the asserted element scrolled into
  frame before its snap, deterministic/opaque fixtures, captions that never claim what the
  pixels don't show. "Thin" describes what you INSTALL, not the capture bar — that stays
  exactly as strict. Record video in whatever the platform captures NATIVELY — Playwright
  `.webm`, Android `adb screenrecord` `.mp4`, iOS `simctl recordVideo` `.mov` — and stop
  there: no client-side ffmpeg, no re-encode. The service transcodes every upload to the
  canonical H.264 ladder (already-valid H.264 passes through untouched) — this removes the
  single most fragile client dependency the classic modes carry (`INGEST-CONTRACT.md` §3.4,
  `SERVICE-DESIGN.md` §9).
- **The MCP client configuration** — service URL, API key, the review-scoped tools
  available in-session. Nothing else.

### The flow

1. **Build the manifest**: `features.json` embedded verbatim as `spec`, a `run` block
   (`startedAt`, `suite`, `metrics` — honest nulls for every gate not yet on, never an
   invented number), and `stories[]` with typed evidence (table below) referencing LOCAL
   attachment paths, not hashes — the client resolves those, not the agent
   (`INGEST-CONTRACT.md` §1, §4.1).
2. **`review_submit_run`** — pass `manifestPath`; every evidence path inside the manifest
   resolves relative to it (a REPLICATION-PROMPT convenience: keeps a large manifest out of
   the model's context the same way local file paths keep bytes out of it). The thin client
   hashes every local attachment, asks the service which it already has, and uploads only
   the missing ones — raw bytes over plain HTTP, never through the model
   (`INGEST-CONTRACT.md` §3.1, `SERVICE-DESIGN.md` §3).
3. **The owner reviews on their phone** via the signed `reviewUrl` link they're notified
   with — no account, same BIEN/FALLA/NOTAS marking the classic modes' artifact already
   uses (`INGEST-CONTRACT.md` §4.1, `SERVICE-DESIGN.md` §5).
4. **`review_wait_for_verdict`** — the thin client polls; returns the per-story verdict
   marked so far: `{ feature, title, state, note }`, `state ∈ bien | falla | unmarked` —
   untranslated, contract-level tokens, never localized (`INGEST-CONTRACT.md` §4.3, §5).
5. **Act on the verdict** — the same triage as the rest of this kit, not a new one: a FALLA
   stays honestly red until fixed, never watered down to force green; a NOTA becomes either
   an adjustment to the behavior or a new tracker issue, following §4's quality-bar triage
   even outside a Mode B burn-down.
6. **`review_accept` with `scope`** — accept per FEATURE as this kit's default practice;
   never invoke wholesale accept out of habit — the contract's wholesale form (omitted/empty
   `scope`) flips EVERY proposed behavior in the run, reviewed or not (`INGEST-CONTRACT.md`
   §4.4), the same silent-baseline risk `--accept-only` guards against in the classic modes
   (`SKILL.md` §6). Pass a `writeTo` path too (the thin client's own convenience, not a
   contract field) so the returned `reviewState`/`metricsHistory`/`spec` land back in this
   repo's tracked files — the service never writes to your repository directly; committing
   them is still on you, and still needs asking first (§1; `SKILL.md` §8).

### Metrics

Quality gates still run IN THIS REPO — code never leaves the machine, only numbers do
(`SERVICE-DESIGN.md` §2). Send them as `run.metrics`: null for every gate not yet on, never
a fabricated number. The service applies the same never-regress ratchet as the classic
modes, informationally — it compares a metric only when non-null in both the current run
and the last accepted row, never coerces null to 0, and never blocks the submission itself;
enforcement stays this repo's own pipeline's job upstream, same as always
(`INGEST-CONTRACT.md` §1.2, §4.1, §4.5).

### Evidence vocabulary (quick reference — `INGEST-CONTRACT.md` §2 is the authoritative schema)

| Type | Shows | Primary material |
|---|---|---|
| `screenshot` | UI truth | the PNG itself |
| `video` | UI truth in motion | the native-capture recording |
| `timeline` | a real-timestamp event sequence | the raw captured event records |
| `state-diff` | before/after of a row, file, or resource | both captured states |
| `artifact` | the thing the job produced | the real file (`.eml`, PDF, CSV, webhook payload) |
| `log-excerpt` | an annotated excerpt, never the sole evidence | the raw excerpt |
| `metric` | a duration or count | the number plus its provenance |

Two rules travel unchanged from the classic modes' screenshot-only world, now generalized
to all seven types: **two faces** — every item has a readable render and downloadable
primary material; they coincide for UI evidence (the screenshot/video IS the material) and
separate for background evidence (the render is presentation, the attachment is the audit
trail) — and **declared truncation, never silent** — showing 50 of 12,000 rows means
`truncation: { shown, total }` is present, always, because a silently-partial view is
indistinguishable from a lie.

### What stays true from the classic modes

- Report prose is in the owner's language — never a default (`SKILL.md` §7).
- Evidence must be VISUALLY true, not just DOM-true: a passing story proves nothing if the
  pixels don't back it (`SKILL.md` §7) — the service validates shape, never visual truth
  (`INGEST-CONTRACT.md` §6.2), so this discipline is entirely on the client, same as always.
- A story that fails stays HONESTLY red until fixed — never deleted or watered down for a
  green badge (`SKILL.md` §8 hard rules; this document's §4 triage).
- Baselines move ONLY via an explicit accept — this kit's default is scoped, per-feature;
  wholesale is never a reflex (`SKILL.md` §6, `INGEST-CONTRACT.md` §4.4).
- Verdict labels — `bien`/`falla`/`unmarked`, the BIEN/FALLA/NOTAS export shape — are
  CONTRACT, untranslated at the data level, whether the report is a local artifact or a
  hosted page (`INGEST-CONTRACT.md` §5, freeze list §7).
