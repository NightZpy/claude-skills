---
name: replicate-behavior-report
description: Install the behavior-report review system in a repo — an async review pipeline where the product owner reviews every feature through ONE artifact-published, self-contained HTML report of captioned E2E behavior stories, enforced by hard quality gates (features.json spec contract, mutation lock, 100% coverage on scope, never-regress ratchet). Use when setting up or adapting the pipeline in a new project of any stack.
---

# Behavior Report — replication skill

You are setting up a **behavior-report review system** in this repository. The product
owner does NOT manually QA or watch terminals: they review every feature asynchronously
(often on a phone) through a single self-contained HTML report published as a Claude
Artifact at ONE permanent URL. Your job: build the pipeline, the report generator, the
spec contract, and the in-repo skill file that makes any future agent operate it correctly.

Everything ships with this skill: `scripts/` (the pipeline stages) and `template/` (the
report generator plus a runnable fixture set — `node template/build-review-report.mjs
--config sample` proves the generator works before you have a suite).

`references/` holds the rest of the former kit, none of it needed for a normal install:
- `REPLICATION-PROMPT.md` — this same specification as a paste-into-any-agent prompt, for
  agents outside Claude Code.
- `INGEST-CONTRACT.md`, `SERVICE-DESIGN.md`, `SERVICE-ANALYSIS.en.html` — the in-progress
  design for a hosted behavior-review service (Mode S, thin client). Read only if you're
  working on the service itself.
- `KIT-README.md` — the standalone kit's original README.

Reference implementation: the `scripts/` folder next to this file (reference flavor —
FastAPI + Postgres backend, Vite + TS frontend). Each script carries an `ADAPT` header.
A worked desktop-app adaptation exists for a VS Code fork / Electron app (`docs/BEHAVIOR-REPORT-PLAN.md`
+ `scripts/report/` + `test/behavior/` in that repo).

## 1. Philosophy (bake this into the in-repo skill you write)

- **The report is the ONLY review medium.** Every feature ships as **behavior stories**:
  E2E tests whose titles are plain-language behavior sentences, narrated with captioned
  screenshots and a GIF recording of the real interaction.
- **Self-review is the point**: the agent proves its own work visually. Hard rule —
  *nothing is declared done in chat that the report doesn't show.*
- **Spec before code.** `features.json` is the durable BDD contract between the user's
  words and the implementation. Behaviors are proposed there FIRST, built second,
  approved by the user's report review third.
- **Honesty is enforced mechanically**: badges expose spec↔suite mismatches; a
  never-regress ratchet stops silent quality decay; failing runs still produce (and are
  worth publishing) a report with the errors expanded.
- Nothing is ever committed without asking the user first; no gate is ever lowered to get green.

## 2. The pipeline — stage contracts (the stable, swappable core)

`full-report.sh` orchestrates the stages below in order. **The contracts are the
generalization**: keep the files each stage writes and its exit semantics identical, and
you may re-body every leaf script for your stack. All data lands in one canonical dir,
`$E2E_DIR/.report-data/` (reference stack: `frontend/e2e/.report-data/`).

| # | Stage | Script | Contract (what downstream depends on) |
|---|---|---|---|
| 1 | Unit tests | (inline) | fast suite passes; orchestrator parses the passed-count |
| 2 | Static gates | `static-checks.sh` | exit≠0 on ANY finding; same list the pre-commit hook runs |
| 3 | Mutation lock | `mutation-tests.sh` | writes `mutation.json` `{total, killed, scorePct}`; exit≠0 below 100% |
| 4 | Dependency audits | (inline) | exit≠0 on high/critical advisories |
| 5 | System tests + coverage + fuzz | `system-tests.sh` | coverage data readable by the orchestrator; **gate = 100% line+branch on the scope** (the gate may live in coverage config, not the script); boundary fuzz (§3); migration round trip if migrations exist; always tears its env down |
| 6 | Report data + metrics + ratchet | `collect-report-data.sh` + inline node | `.report-data/`: `unit-tests.txt`, `system-tests.txt`, `fixtures.json`, optional `schema.json` + `migrations.json`; then `metrics.json` (keys below); **never-regress invariant** vs `metrics-history.json` |
| 7 | E2E stories + report | `e2e-tests.sh` | runs stories, then **ALWAYS** rebuilds the report HTML — even on failure; exits with the test status |

`metrics.json` keys (the contract with the generator's dashboard): `generatedAt`,
`unitTests`, `systemTests`, `coveragePct`, `statements`, `branches`, `missedLines`,
`mutants`, `mutationKilled`, `mutationScorePct`, `duplicationPct`, `duplicationClones`.
`hygiene.sh` writes `hygiene.json` `{duplicationPct, clones, duplicatedLines}`.

**Scoped runs must not clobber canonical results** (field lesson): the E2E runner's JSON
reporter OVERWRITES its results file with only the specs that ran — a single-spec debug run
silently poisons the next report (everything else reads as NO STORY). Debug scoped runs
with a reporter flag that skips the JSON output (Playwright: `--reporter=list`); only
full-suite runs may write the results file — and the FINAL full run must pass NO reporter
flag at all (a CLI `--reporter` on the full run also suppresses the config's JSON output,
leaving the generator reading stale results that contradict the run you just watched;
detectable by comparing the results file's startTime against the run). Cosmetic generator changes regenerate from the
existing results in seconds — they never require a suite run.

**Never-regress ratchet** (in `full-report.sh`, vs the last row of `metrics-history.json`):
coverage and mutation score never drop, duplication never rises. It exists to catch gate
tampering — the gates upstream should make it unreachable. **Compares a metric only when
it is non-null in BOTH rows** (current run and the last accepted one) — null on either side
is skipped, never coerced to 0 and never treated as a regression: gates come online
incrementally (staged adoption), so metrics stay null for long stretches, and a naive
ratchet would crash or false-fire the instant a staged gate goes live — teaching owners to
distrust or bypass the ratchet.

**Single-entry rule**: wire the pipeline into the repo's existing runner (`run.sh`,
`Makefile`, npm scripts) so there is one obvious command, not a scripts folder to memorize.

## 3. Tools by concern — swap per stack

| Concern | Reference stack | Swap guidance |
|---|---|---|
| E2E stories + recordings | Playwright chromium, `video: on`, `workers: 1`, one shared live env per run | desktop app → Playwright `_electron.launch` (see §10); keep serial workers |
| GIF encoding | **ffmpeg-static** (npm) | keep; dials in §6 |
| Isolated test envs | docker compose per suite, own project name + ports, tmpfs DB, teardown on EXIT even on Ctrl-C | desktop app → throwaway user-data dir (§10); anything → "disposable env beside the dev stack" |
| Fast unit suite | pytest + in-memory SQLite session-override | your fastest DB double — it must be milliseconds-fast; the mutation lock reruns it hundreds of times |
| Mutation lock | **mutmut**, scope = behavior core (routers + security + domain logic), gate 100% killed | JS/TS → **Stryker**; always scope explicitly, never the whole tree |
| System suite + coverage | pytest over HTTP vs the real dockerized backend; coverage started via `exec` so SIGTERM flushes; gate 100% line+branch | keep the "real deployment shape" property; coverage gate can live in config (`fail_under`) |
| **Fuzz the trust boundary you have** | **schemathesis** (OpenAPI, fixed seed, authenticated; any 500 fails; "unsupported method → 405" catches route shadowing) | no HTTP API? fuzz your actual boundary: internal tool seam → property-based (fast-check / Hypothesis); CLI → arg fuzz. The invariant: *malformed input yields a structured refusal, never a crash* |
| Contract types | openapi-typescript → generated `.d.ts`, `--check` fails when stale | only for multi-language repos; single-language/native-TS → delete this stage |
| Static gates | ruff, pyright, bandit, xenon (≤B/function), tsc, oxlint, gitleaks | your stack's equivalents; ONE script, also run by the pre-commit hook |
| Design tokens | grep banning raw hex / arbitrary color classes in `src/` | adapt patterns + allowed files to your token system |
| Dead code | knip (frontend); backend needs none — 100% coverage already kills it | any language with a knip-equivalent |
| Duplication | jscpd: hard gate (0 clones ≥70 tokens in prod code) + ratcheted metric (% at ≥50); tests/e2e/generated excluded by design | keep both gate and metric |
| Dependency audit | pip-audit + npm audit | your ecosystem's auditor |
| Publishing | Claude **Artifact tool**: one URL forever, one favicon, labeled versions | keep |

## 4. Files to create

```
scripts/full-report.sh            the one command (stage order in §2)
scripts/static-checks.sh          all static gates (same list as the pre-commit hook)
scripts/mutation-tests.sh         mutation lock → mutation.json, fails <100%
scripts/system-tests.sh           isolated env, system suite, coverage gate, fuzz, migrations
scripts/e2e-tests.sh              isolated env, stories (extra args pass through), ALWAYS rebuilds report
scripts/hygiene.sh                dead code + duplication → hygiene.json
scripts/contract-types.sh         only if multi-language (see §3)
scripts/collect-report-data.sh    schema/migrations (if any), test-id lists, fixture contents
.githooks/pre-commit              static-checks.sh + unit suite; activate via git config core.hooksPath
$E2E_DIR/features.json            the BDD contract (§5)
$E2E_DIR/fixtures.ts              wraps the test framework: injects click-ripple + focus flash
                                  (recordings show WHERE clicks land), sets slowMo for readable GIFs
$E2E_DIR/helpers.ts               API seeding (never seed via UI), snap(), noteSeed(), uniqueDigits(),
                                  signIn(); every seeding helper calls noteSeed('<run-stable text>')
$E2E_DIR/<feature>.spec.ts        one spec per feature; describe title == features.json key EXACTLY
$E2E_DIR/visual.spec.ts           pixel baselines (NO ripple fixture — it flakes pixels); fixed
                                  reserved identifiers, masked timestamps, maxDiffPixels ≈ 60
$E2E_DIR/build-review-report.mjs  the generator (§6)
$E2E_DIR/review-state.json        accepted baselines — NEVER hand-edited; only --accept writes it
$E2E_DIR/metrics-history.json     one row per accepted report — same rule
.claude/skills/behavior-report/SKILL.md   the OPERATING manual for future agents: the one command,
                                  file map, exact publish steps, spec rules, mutation playbook,
                                  troubleshooting, hard rules (§8) (path may vary — `.claude/` is
                                  often gitignored; confirm the repo's actual tracked skills path)
```

## 5. The behavior spec (`features.json`)

```json
{
  "<Feature name>": {
    "askedFor": "faithful paraphrase of what the user requested — their words, not yours",
    "behaviors": {
      "a behavior sentence in plain language": {
        "status": "proposed | approved",
        "done": ["1–4 terse, observable completion conditions the story actually proves"]
      }
    }
  }
}
```

Optional per-feature field `"issues": ["#122", "#130"]` — tracker references the generator
renders as links to the repo's issue tracker in the feature header. Division of labor: the
report tracks spec↔proof truth (badges), the tracker tracks work (issues, one per work item
— never one per behavior); the links bridge the two. Commits reference their issue (`#N`)
in the message so the tracker links them automatically.

Rules: story titles join to behavior titles by EXACT string match. The report cross-checks
both directions — agreed behavior without a story ⇒ **NO STORY** badge (red, open, shows
its conditions; "the feature may exist, the report can't vouch for it"); story without an
agreed behavior ⇒ **UNSPECIFIED**. Neither fails the pipeline; neither may be published
silently. Never reword an approved behavior quietly — retitling surfaces as NO STORY +
UNSPECIFIED, which is the system catching you.

**Flow for every feature request:** (1) draft proposed behaviors first and show the user a
compact list; (2) stop only for real product decisions you can't infer; (3) build;
(4) publish; (5) `--accept` flips proposed→approved after the user's review.

## 6. The report generator (`build-review-report.mjs`)

**Start from [`template/build-review-report.mjs`](template/build-review-report.mjs)** — copy
it into your repo, fill in its `CONFIG` block (product name, paths, owner-facing `STRINGS`),
and run it. Do not re-author the generator from the prose below; the template already
implements this section end to end, field-tested in production — this section is the
**CONTRACT** it implements (badges, verdict format, media scoping, accept semantics).
Redesign the HTML/CSS/JS freely; keep the contract. `template/README.md` has the smoke-run
instructions (`node build-review-report.mjs --config sample`, no real suite needed).

Single self-contained HTML (inline CSS/JS, data-URI media). **Sections are data-driven and
optional** — a stack with no DB simply has no Database section; the generator renders what
`.report-data/` contains.

**Design principles (field-tested):** the reader is the HUMAN WHO DIRECTS THE AGENT,
reviewing asynchronously, usually on a phone. The page must answer three questions in
order: (1) what needs my attention now? (2) what evidence backs it? (3) approve or flag?
Attention-first hierarchy: failing → CHANGED → NEW/PROPOSED stories as full cards, in that
order; APPROVED unchanged stories collapse to one-line expandable rows; NO STORY behaviors
render as a compact per-feature burn-down list (title + done-conditions behind a tap, a
gap-count badge per feature, one summary line up top) — an honest map, never a wall of red
noise. Phone-first: ≥16px body, ≥40px tap targets, the nav sidebar becomes a jump menu on
narrow screens, no horizontal page scroll. Zero decoration that doesn't inform.

1. **Header**: title, pass/fail/new/changed counts, timestamp, a **filter-chip bar** with
   live counts — All · Attention (new+changed+failing) · Failed · Changed · New · Proposed
   · No story · Approved — single-select, persisted, filtering story cards, collapsed
   rows, burn-down rows AND the nav entries (feature sections hide when empty under the
   filter; an honest "nothing matches" note otherwise), a collapsible **"What the badges
   mean" legend** — each badge chip with a one-line meaning a non-engineer understands —
   and a **"How to use this report" guide** (collapsible, OPEN by default until dismissed;
   dismissal persisted): an action-oriented "if you see this → do this" mapping (card with
   evidence → watch, mark ✓/✗ + note · FAILED → the agent already knows; note only adds
   context · NO STORY → did NOT fail, it's the promised-but-unproven backlog, nothing to do
   · CHANGED → re-review · badges are independent facts, not stacked severity) plus the
   4-step loop: review attention items → mark → copy verdict → paste it to the agent's CLI.
2. **Metrics dashboard**: cards + sparklines from history — E2E behaviors (happy/edge
   split), unit/system counts, coverage %, mutation score, duplication %, visual checks,
   behavior-spec card (proven/total + proposed/no-story/unspecified), "new this report".
   History appends one row per `--accept`; tolerate missing fields in old rows (render "—").
3. **Behavior scenarios**, grouped by feature, each headed by the `askedFor` text (label
   it in the product language, e.g. "Lo que pediste" — an example in the owner's language,
   localized like every owner-facing label) and, when the feature declares
   `issues`, links to those tracker issues. Each story: badges — PASS/FAIL,
   HAPPY PATH/EDGE CASE, NEW, CHANGED, PROPOSED, UNSPECIFIED — captioned screenshots
   presented as a **lightbox gallery** (tapping a shot opens it enlarged and readable —
   phone-first; prev/next via on-screen arrows, ←/→ keys and swipe; the caption and a
   "3 / 5" position indicator render below the enlarged image; Esc or backdrop-tap closes;
   background scroll locked while open), a
   GIF of the interaction, and a per-story "prepared off-camera (via API)" list rendered
   from the seed annotations. Failures auto-expand with error text. A nav sidebar lists
   every feature/story with attention dots.
4. **Database** (only if schema/migrations data exists): per-migration SQL with NEW
   badges, plus an ER diagram of the live schema diffed against the accepted baseline
   (green added / amber changed / red removed).
5. **API / surface** (only if surface data exists): endpoints (or tools/commands)
   content-hashed for NEW/CHANGED badges, schemas field-by-field, fixture files, and the
   unit/system test-id listings.

Mechanics that make it work:
- **Content hash per story** = title + captions + done conditions + seed annotations.
  Hash drift vs `review-state.json` ⇒ CHANGED. Seed texts must be run-stable (no unique
  IDs) or stories re-flag every run.
- **Media scoping** (keeps the file under the Artifact's ~16MB cap forever): only NEW /
  CHANGED / failing / PROPOSED / UNSPECIFIED stories embed media. Unchanged approved
  stories keep their entry + done list with a note pointing at previous artifact versions.
  `--refresh "<feature>"` re-embeds one feature's media without touching baselines;
  `--compact-gifs` (smaller scale/fps/colors) for full-catalog rebuilds.
- **Story recording — video first, GIF only as fallback** (field-corrected; the owner needs
  playback CONTROLS, which a GIF cannot give): re-encode the runner's webm →
  H.264 MP4 (`-c:v libx264 -pix_fmt yuv420p -crf 27 -vf scale=1024:-2 -an`; H.264 for
  iPhone-Safari), embed as `data:video/mp4;base64` in `<video controls playsinline
  preload="metadata" poster="<first-shot data-URI>">` plus a small speed bar
  (0.5×/1×/1.5×/2× via `playbackRate`) — real-time speed replaces any baked slowdown; no
  autoplay. Size ladder before degrading: crf 27→28→30, then scale 1024→900→760; print the
  dials + per-story sizes. Keep the GIF pipeline as an automatic fallback when no H.264
  encoder exists — floored at scale 760 / 96 colors / fps 8, NEVER lower (440/40 compact
  dials produce unreadable mush). **Never display media above its encoded width**
  (`max-width: min(100%, <encoded>px)`) — upscaling doubles the blur. If the floor still
  doesn't fit the budget, the answer is media scoping, never mushier media.
- **Evaluated and rejected: DOM session-replay (Datadog/rrweb-style) instead of video.**
  Tempting when media was GIF-heavy, but with the H.264 pipeline a story video costs
  ~35-90KB — less than an inlined rrweb player (~150-200KB) plus per-session JSON plus the
  app's CSS per snapshot. And the deeper objection is honesty: DOM replay is a
  RECONSTRUCTION — canvas content (PDF viewers) isn't captured by default, custom elements
  (icon web components) and webviews replay poorly, so evidence could look fine while the
  real pixels were broken (or vice versa). Video is pixel ground truth — the currency this
  system trades in. Revisit only for plain-DOM web apps with very long sessions where
  scrubbing/inspection outweighs fidelity; never as the default.
- **Captioned screenshots open in the lightbox gallery** (see section 3); done-condition
  checkmarks are HONEST: ✓ only when a passing story backs them; unproven (NO STORY /
  proposed-without-pass) or failed stories show a neutral marker instead.
- - **Story cards are collapsible — marking collapses them** (triage flow): every story card
  can collapse to its one-line row (title + badges). Default state: OPEN for attention
  items (failing / CHANGED / NEW / PROPOSED), collapsed for approved-unchanged. When the
  owner marks a card (ok or fails), it AUTO-COLLAPSES — the mark is the "done reviewing
  this one" gesture, so the page drains as the review progresses; reopening is one tap.
  A marked card shows its verdict AT A GLANCE with color (designer's call on treatment —
  border accent, edge tint): ok → success family, fails → failure family, unmarked →
  neutral. Keep the owner-verdict color visually distinct from the PASS/FAIL badge chips
  (test result ≠ owner verdict); apply consistently to full cards, collapsed rows and
  burn-down rows. While an OPEN card taller than the viewport is being reviewed, the
  card header (title + badges + mark control) stays sticky so marking/noting never
  requires scrolling back up.
**Review-marking + plain-text verdict export** (the owner's steering wheel; the artifact
  can't reach any server, so localStorage + clipboard IS the design): every story card and
  NO STORY row carries a toggle `unmarked → ✓ ok → ✗ fails` plus an optional note;
  persisted in localStorage keyed by feature+title with the story's content hash (hash
  drift ⇒ "stale mark" hint). A sticky export bar shows live counts and **"Copy verdict"**
  builds plain text the agent parses VERBATIM (labels are a contract, in the owner's
  language):
  ```
  VEREDICTO DEL REPORTE — <generatedAt>
  BIEN (n):    - <feature> :: <story title>
  FALLA (n):   - <feature> :: <title> — nota: <text>
  NOTAS (n):   - <feature> :: <title> — <text>
  SIN MARCAR: <n>
  ```
  Clipboard via `navigator.clipboard` with a MANDATORY pre-selected-modal fallback. The
  owner pastes the verdict into the agent's CLI: BIEN feeds acceptance, FALLA opens a fix
  cycle before accept (the note is the spec), NOTAS go to triage.
- **`--accept`** (run exactly once, AFTER publishing): promotes all baselines (scenario
  hashes, surface hashes, schemas, migrations, DB schema), appends one metrics-history row
  (idempotent on identical runs), flips every proposed behavior to approved. Cosmetic
  republish of the same run ⇒ skip accept. **`--accept-only "<feature>"` (repeatable) —
  verdict-scoped accept**: when the owner's verdict covers only a subset (big burn-down
  batches), promote and baseline ONLY the named features; wholesale `--accept` would
  silently baseline never-reviewed stories and drop their media from the next version.
  Accept exactly what the verdict marked ok — nothing more.

## 7. Writing stories

- Happy path AND edge cases (`{ tag: '@edge' }`); edge stories are mandatory per feature.
- Seed through the API with unique identifiers per test; never through the UI; never share state.
- Narrate with `await snap(page, testInfo, 'caption')` 3–6 times per story. Captions are
  present-tense, specific, and HONEST — oddities go in the caption, not under the rug.
- **Recordings must BREATHE** (owner objection, field-confirmed): raw automation fires
  actions in milliseconds — UI states never finish loading on camera before the next click.
  Pace at RECORD time (playback speed can't fix skipped states): `slowMo` ~400-500ms on the
  launch (or a paced-action fixture helper if the launch path ignores slowMo), plus
  assertions that gate on the loaded state before acting. Baked slowdowns (GIF setpts) or
  slow playback are complements, not substitutes.
- **Evidence must be VISUALLY true, not just DOM-true** (field lesson — the owner failed two
  passing stories from the report media): snap only AFTER async rendering completes (images:
  `naturalWidth > 0` / decode; canvases: render-promise done + a painted-pixel check), scroll
  the asserted element into frame before its snap (full-page shots miss inner-scroll
  content), and use OPAQUE test fixtures (a transparent 1x1 PNG renders perfectly and shows
  nothing). A caption may never claim what the pixels don't show.
- Assert what the user sees (visible UI text in the app's language), not implementation
  details. Prefer `getByRole`/`getByPlaceholder`; scope repeated controls to their
  row/panel to avoid strict-mode collisions.
- Report prose/captions in the language the product owner reviews in; app UI and asserted
  strings in the product language.

## 8. Publish workflow + hard rules (verbatim into the in-repo skill)

Publish: run `./scripts/full-report.sh` → strip ONLY the skeleton tags (`<!doctype>/<html>/<head>/<body>`)
into a scratchpad file — the Artifact tool adds its own wrapper; KEEP `<title>`, the inline
`<style>`/`<script>` and `<meta name="viewport">` (without it phones render desktop-width) → publish with the
Artifact tool to the ONE existing artifact URL (pass `url:` from a new session; same
favicon forever; label each version) → summarize honestly in chat (counts, what's NEW,
anything odd) → `--accept` once → ask before committing.

Hard rules: never hand-edit `review-state.json`/`metrics-history.json`; `--accept` only
right after publishing, exactly once; never lower coverage/mutation gates, skip failing
tests, or delete scenarios to get green; one artifact URL, one favicon; every feature
ships with spec entry + happy/edge stories + system tests to 100% + surface-manifest
update + mutation scope membership with all mutants killed; pre-commit hook never bypassed
with `--no-verify` without explicit approval; ask before `git commit`, always; nothing is
declared done in chat that the report doesn't show.

Also pin a **surface-manifest test** asserting the exact list of your boundary's entries —
HTTP routes, agent tools, CLI commands, whatever the product exposes — so adding/removing
one is always a conscious, reviewed act.

## 9. Mutation-lock playbook (include in the in-repo skill)

Survivor ⇒ show its diff ⇒ write a unit test that fails under that diff (assert observable
behavior: status codes, exact detail strings, ordering, row identity). Equivalent mutants
are resolved by RESTRUCTURING, in order: hoist literals to module constants (module level
isn't mutated) → drop redundant args → make "optimization-only" code load-bearing (e.g.
pre-key a dict with expected ids so a widened query fails loudly instead of silently
passing) → move unobservable in-process ordering into the storage layer's `order_by`, or
make ordering observable with same-key test data → suppress-comment (`# pragma: no
mutate` / Stryker disable) with inline justification as the LAST resort. Keep request-time
logic out of import-time code (decorators/factories can't be mutation-tested). Keep date
logic pure (`today` as a parameter) so it stays lockable and clock-stable.

## 10. Desktop-app appendix (Electron / native)

The web-stack concerns map, they don't disappear:

| Web (reference) | Desktop analog |
|---|---|
| docker compose env, tmpfs DB, own ports | launch the app with a **throwaway user-data dir** (mkdtemp), disposable beside the dev instance; delete on teardown |
| Playwright browser + `video: on` | **Playwright `_electron.launch({ executablePath, args, recordVideo })`** — same locators, native video → same GIF dials. Fallback if the app's boot fights `_electron`: `connectOverCDP` to the app's debug port and capture GIF frames via CDP screencast |
| HTTP `/health` wait loop | `app.firstWindow()` + wait for a root selector |
| seed via API | seed via the app's backend/IPC/CLI surface — still never via the UI |
| schemathesis over OpenAPI | property-fuzz the app's internal trust boundary (§3) |

Worked example: the desktop-app adaptation's `docs/BEHAVIOR-REPORT-PLAN.md` + `scripts/report/`.

---

**Definition of done for the setup task:** `./scripts/full-report.sh` runs green end-to-end
on a demo feature with at least one happy + one `@edge` story; the report renders its
sections with correct badges and the legend; `--accept` round-trips (second build shows
zero NEW/CHANGED); the pre-commit hook is active; and the in-repo
`.claude/skills/behavior-report/SKILL.md` (or wherever the repo actually tracks agent
skills, e.g. `.agents/skills/`, if `.claude/` is gitignored) documents all of the above so a
fresh agent can operate the pipeline without this kit.
