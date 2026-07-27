# Behavior Report Service — design proposal

**Status: PROPOSAL** — nothing here is built. The kit as it exists (replication-based) remains
the working product until this ships. Captured from owner design conversation, 2026-07-06.

## 1. Vision — invert the distribution

Today the kit is *replicated*: every repo installs its own generator + pipeline + docs and
adapts them to its stack. The service inverts that: one central web service with an MCP
interface. Any agent (Claude or any LLM), from any repo, installs nothing — it sends only the
dynamic data (spec, story results, screenshots, videos, captured artifacts) and gets back a
generated, hosted, reviewable report. The owner's verdict closes the loop back to the agent
through MCP instead of manual copy/paste.

Why the kit is already halfway there: the template's CONFIG + STRINGS + `PRODUCT_NAME`
generalization is exactly the multi-product parameterization a service needs, and the
generator is already in essence a pure function `(spec, results, media, strings) → HTML`.
The SKILL.md §6 contract (badges, verdict format, accept semantics, content-hash) becomes
the API contract.

## 2. The split — what runs where

| Client side (agent on the user's machine) | Service side |
|---|---|
| The app under test on any platform (web / mobile emulator-simulator / desktop / daemon) + deterministic fixtures and seeds | API + MCP surface (`submit_run`, `get_report`, `get_verdict`, `accept`, `accept_only`) |
| `features.json` — the spec lives versioned in the repo (source of truth for the WHAT); sent with each run | Ingest validation (manifest completeness, media validity, evidence-contract checks) |
| E2E stories (Playwright or stack-appropriate) — run against the local app | **Media encoding**: receives raw recordings, applies the H.264/GIF ladders itself (floor 760 / 96 colors) — ffmpeg disappears from the client |
| **Evidence capture**: real browser, paced actions (~400–500 ms), decode/paint gates, screenshots, raw video; for background behavior: capturing rows/files/payloads *at run time* | Report generation (today's generator, parameterized per project/language) |
| Quality metrics computed locally (coverage, mutation, duplication — code never leaves the machine; only numbers are sent) | Hosting with per-project auth; media served same-origin |
| A thin client: local MCP server (stdio) or minimal CLI that packages manifest + file paths and uploads | Owner verdict persisted server-side, readable by the agent via `get_verdict` |
| Repo integration: hook/CI trigger, baseline state versioned in git | Metrics ratchet + per-project history |
| | LLM layer (final phase — see §7) |

Consequences:

- The client becomes **thin**: the ~2,000-line generator, ffmpeg encoding, and HTML assembly
  leave every repo.
- REPLICATION-PROMPT shrinks from "install the whole kit" to "write stories and capture
  valid evidence" — an **ingest contract**, not an installation manual. The capture-side
  doctrine (pacing, decode/paint gates, visually-true evidence, opaque fixtures) stays
  client-side and becomes the heart of that contract.
- What the service can never do: reach into the client's app, DB, or filesystem. If a story
  didn't capture it at run time, it doesn't exist as evidence.

## 3. Binary transport — never through the model

MCP tools exchange JSON; video/screenshots must not travel as base64 through an LLM context.
Two acceptable shapes (pick at spec time):

1. **Local stdio MCP server** (preferred): the agent passes local file *paths*; the local
   server reads them and uploads via plain HTTP to the service. The model never moves bytes.
2. Remote MCP + pre-signed upload URLs returned by `submit_run`.

## 4. Evidence vocabulary — UI and background behavior

The kit today only knows visual evidence (screenshot / H.264 video / GIF fallback) because
its object is UI. Daemons and background jobs have no pixels — but they always have
**observable effects**: files written, rows changed, emails sent, queues drained, webhooks
fired. The contract gains an evidence vocabulary with a standard renderer per type:

| Type | What it shows | Primary material attached |
|---|---|---|
| `screenshot` / `video` | UI truth, unchanged doctrine (H.264 primary, GIF fallback, never displayed above encoded width) | the image / the recording itself |
| `timeline` | real-timestamp event sequence ("02:00:00 order arrived → 02:00:03 worker picked it up → 02:00:04 email sent") | the event records |
| `state-diff` | before/after of a file, table, bucket, API resource | both captured states (e.g. the actual row as JSON) |
| `artifact` | the thing the job produced, rendered when previewable | the real file: the `.eml` as it arrived, the PDF, the CSV, the webhook payload, the request/response pair |
| `log-excerpt` | annotated excerpt, collapsed as auditable detail — never primary evidence | the raw excerpt |
| `metric` | durations, counts | the numbers + provenance |

**Every evidence item has two faces**: a readable render (the presentation) and the
**accessible primary material** (download/inspect: the file itself, the captured insert/row,
the payload). For UI evidence the two coincide — the screenshot *is* the material. For
background they separate: the render is presentation; the attached material is the auditable
ground truth. Manifest shape per item: `{type, caption, attachment(s), metadata (timestamp,
origin)}`.

Rules carried over from kit doctrine:

- Truncation is always declared ("showing 50 of 12,000 rows"), never silent.
- Primary materials can carry sensitive data → deterministic/synthetic fixtures remain the
  doctrine, plus configurable per-project redaction for what can't be synthetic.
- Verdict mechanics don't change: same stories, same badges, same BIEN/FALLA/NOTAS — only
  the evidence type varies.

## 5. Review UI — standardized, mobile/PC

One frontend, owned by the service, consuming the run's JSON — replacing per-repo replicated
HTML. Designed review-first:

- Story-by-story review queue, full-screen evidence, one-tap verdict marks on mobile,
  higher density on desktop, visible progress ("reviewed 7/12").
- The mobile doctrine already proven in the kit (no horizontal scroll at 360/390 px,
  lightbox gallery, tap targets) becomes the frontend's baseline, implemented once.
- The self-contained HTML (strict CSP, zero external requests) is demoted from *the*
  product to an **export format** — offline archive / share-without-service — and keeps the
  §6 verdict text contract as its export shape.
- Hosted media is served same-origin (lighter than base64-inline). This consciously relaxes
  the "zero external requests" rule for the hosted view only; the export keeps it.

## 6. Open decisions (must be resolved at spec time)

1. **Baseline state**: stateless service (review-state/metrics-history stay versioned in the
   client repo and travel with each run — preserves today's git auditability) vs
   accept-from-hosted-UI (owner accepts where they review — better UX, but baseline then
   lives server-side and needs sync-back to the repo). Current recommendation: stateless
   baselines; server-side only for the verdict. Accept-from-UI is tempting — decide
   consciously, not by drift.
2. **Multi-tenant auth**: API keys per project, media retention windows, private report URLs.
3. **Contract versioning**: the evidence vocabulary extends `features.json` + the ingest
   manifest — a conscious, versioned spec change. §6 verdict semantics remain unchanged.

## 7. LLM layer — DEPRIORITIZED (owner decision 2026-07-06: build last)

The service can run its own LLMs over submitted runs before the human reviews. Deferred to
the final phase; recorded so the design doesn't lose it:

- **Evidence QA** (multimodal): flag visually-false evidence before the owner sees it —
  blank screens, half-loaded states, screenshot contradicting its caption. Centralizes what
  today depends on each client agent's discipline.
- **Editorial**: consistent captions/prose in the owner's language; executive summary of the
  run ("what changed since last accept, where to look first").
- **Triage**: order stories by risk, group related failures.
- **Spec↔evidence drift**: stories that pass while their evidence shows something else.
- For background evidence: translating structured material (timelines, diffs) into the
  owner-language narrative, with the raw material attached beneath.

Hard boundary regardless of phase: the LLM **annotates, organizes, and filters — it never
issues the verdict**. BIEN/FALLA/NOTAS belongs to the human; the captured material remains
the only ground truth. LLM processing of private media/materials is per-project opt-in.

## 8. Rough phasing

1. **Service core**: ingest + validation, media encoding, report generation, hosting + auth,
   verdict persistence, MCP surface, thin client. UI evidence only (parity with today's kit).
2. **Evidence vocabulary**: background/daemon types (timeline, state-diff, artifact…) with
   primary-material attachments.
3. **Review-UI maturation**: the review-first queue UX, PC density, export polish.
4. **LLM layer** (last, per owner decision).

The kit's current replication path stays supported until phase 1 reaches parity — repos in
the field keep working; the service is an alternative consumer of the same contract, not a
breaking change.

## 9. Decision log

**Phase 0 ships as a module of an existing platform, not a standalone stack.** Where a host
platform already provides an artifacts pipeline (content-addressed dedup), worker ffmpeg, a
multi-tenant DB, notifications and metering, build the service as a module against those:
a `review-core` package (project/run/story/evidence/verdict/baseline domain + the kit's
generator ported as the renderer, keeping the self-contained HTML export), a `/v1/review/*`
API namespace, MCP tools under a `review` scope, and a separate lightweight review app for
the owner's mobile-first queue (signed-link access, no account). Boundary rules: clean
module edges so it stays extractable later, the kit's §6 contract implemented unchanged
(the kit remains the capture contract and the replicable fallback), and the host platform's
own roadmap never blocked by this workstream.

**Media encoding is server-side.** Clients upload whatever their capture tool
produces natively (Playwright `.webm`, Android `adb screenrecord` `.mp4`, iOS `simctl
recordVideo` `.mov`); the service transcodes once to the canonical H.264 ladder. Ingest
also accepts already-valid H.264 as-is (no re-encode), so kit-era clients that still encode
locally keep working. WHY: removes the client's most fragile dependency (ffmpeg/libx264 —
the field scar that created the kit's whole GIF-fallback machinery), guarantees uniform
ladder output across projects and machines, keeps universal iOS/Safari playback with native
controls, and stored masters allow retroactive re-encoding when the ladder improves.
