# Behavior Review Service — Ingest Contract (v1)

**DRAFT v0 — pending owner review**

Grounded in `docs/SERVICE-DESIGN.md` (architecture, evidence vocabulary §4, decision log §9)
and `SKILL.md` §5–§6 (the `features.json` spec shape and the report-generator CONTRACT:
badges, verdict format, accept semantics, content-hash). Where this document states a rule
that also exists in `SKILL.md` §6, it is **preserving that semantics unchanged**, not
reinventing it — §6 remains the reference implementation; this is its service-side contract.

This is an **implementation-neutral wire/API contract**: no runtime, database, or hosting
stack is assumed. Any client that already speaks the existing report-generator contract
(badges, verdict, accept, content-hash) can adopt this service with no behavior change on
its own side.

## Contents

1. [Manifest schema](#1-manifest-schema)
2. [Evidence vocabulary](#2-evidence-vocabulary)
3. [Blob protocol](#3-blob-protocol)
4. [MCP tool surface](#4-mcp-tool-surface)
5. [Verdict shape](#5-verdict-shape)
6. [Ingest validation](#6-ingest-validation)
7. [Versioning](#7-versioning)

### Terms

- **Project** — one client repo/product registered with the service.
- **Run** — one submission of suite results + evidence + metrics for a project.
- **Story** — one behavior-scenario result; maps 1:1 to a `features.json` behavior.
- **Feature** — one top-level key of `features.json`, grouping behaviors.
- **Evidence item** — one attached piece of proof for a story.
- **Blob** — one content-addressed payload referenced by evidence items.
- **Baseline** — the accepted-state pair `{reviewState, metricsHistory}` a project's last
  accept produced.

---

## 1. Manifest schema

The table below is the **wire-level** shape — what actually reaches the ingest service
after the thin client resolves local files to blob references (§3, §4.1).

| Field | Type | Required | Notes |
|---|---|---|---|
| `contractVersion` | string | yes | e.g. `"1.0"`. See §7. |
| `projectId` | string | yes | Opaque, issued at project registration (out of scope for this doc). |
| `spec` | object | yes | The project's `features.json`, embedded **verbatim** — same shape as `SKILL.md` §5. Never redesigned, never partial. |
| `baseline` | object \| null | yes | `{ reviewState, metricsHistory }` from the client's last accept, or `null` on a project's first-ever run. See §1.3. |
| `run` | object | yes | `{ startedAt, suite, metrics }`. See §1.2. |
| `stories` | array\<Story\> | yes | One entry per executed story. See §1.4. |

### 1.1 `spec` (features.json, verbatim)

```json
{
  "Bienvenida": {
    "askedFor": "que la app salude a la persona al entrar y le deje exportar el reporte visible",
    "issues": ["#122"],
    "behaviors": {
      "la persona ve un mensaje de bienvenida al abrir la app": {
        "status": "approved",
        "done": [
          "aparece el saludo con el nombre de la app",
          "el botón de continuar queda visible y habilitado"
        ]
      }
    }
  }
}
```

`issues` is optional (per feature). The service never rewrites this object except through
`accept`'s `status` flip (§4.4), and always by **returning** a full replacement for the
client to write back — the service never edits the client's repository directly.

### 1.2 `run`

| Field | Type | Required | Notes |
|---|---|---|---|
| `startedAt` | string (ISO 8601) | yes | When the client's suite began executing. |
| `suite` | string | yes | Free-text suite label, e.g. `"e2e"`. |
| `metrics` | object | yes | See below. **Every key is nullable; null means "not measured," never 0** — the never-regress ratchet (§7 freeze item 6) depends on this distinction. |

`metrics` keys — identical to `metrics.json` in `SKILL.md` §2, unchanged, not renamed:

| Key | Type |
|---|---|
| `generatedAt` | string \| null |
| `unitTests` | number \| null |
| `systemTests` | number \| null |
| `coveragePct` | number \| null |
| `statements` | number \| null |
| `branches` | number \| null |
| `missedLines` | number \| null |
| `mutants` | number \| null |
| `mutationKilled` | number \| null |
| `mutationScorePct` | number \| null |
| `duplicationPct` | number \| null |
| `duplicationClones` | number \| null |

### 1.3 `baseline`

v1 adopts the stateless-baseline recommendation from `SERVICE-DESIGN.md` §6 (open decision
1): baseline state travels with every run rather than being held server-side, preserving
git auditability. `baseline` is `null` only on a project's first submitted run.

```json
{
  "reviewState": {
    "acceptedAt": "2026-07-01T10:00:00.000Z",
    "features": ["Bienvenida"],
    "scenarios": {
      "Bienvenida la persona ve un mensaje de bienvenida al abrir la app": "a1b2c3d4e5f60718"
    }
  },
  "metricsHistory": [
    {
      "acceptedAt": "2026-07-01T10:00:00.000Z",
      "runContentHash": "9f8e7d6c5b4a3210",
      "behaviorsPass": 4,
      "behaviorsTotal": 5,
      "behaviorsHappy": 3,
      "behaviorsEdge": 2,
      "unitTests": 40,
      "systemTests": 12,
      "coveragePct": 100,
      "mutationScorePct": 100,
      "duplicationPct": 0
    }
  ]
}
```

Both sub-objects are byte-for-byte what the client currently holds on disk as
`review-state.json` / `metrics-history.json` (`SKILL.md` §4). The service treats them as
input for hash comparison and ratchet computation and does not persist them beyond the
request's lifetime. `accept` returns updated copies of both for the client to write back
and commit (§4.4). Note the history row is a **curated subset** of `run.metrics` (no
`statements`/`branches`/`missedLines`/`mutants`/`mutationKilled`/`duplicationClones` —
those live only in the per-run `metrics` object, not in history), matching
`buildHistoryRow()` exactly.

### 1.4 `stories[]`

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Client-chosen, unique within the run. Used for intra-run evidence referencing and hosted-UI anchors only — **not** the cross-run identity key. |
| `feature` | string | yes | Must exact-match a key in `spec`. |
| `title` | string | yes | Must exact-match a behavior sentence under `feature` in `spec` for the story to resolve against an agreed behavior; otherwise the service classifies it UNSPECIFIED (badges, §5). |
| `status` | `"pass"` \| `"fail"` | yes | Client-observed result for this story. |
| `isEdge` | boolean | yes | `true` → EDGE CASE badge, `false` → HAPPY PATH badge. |
| `seeds` | array\<string\> | no (default `[]`) | Off-camera prep annotations; must be run-stable text (no unique IDs), or the story re-flags CHANGED every run. |
| `durationMs` | number \| null | no | Informational. |
| `errorText` | string \| null | no | Present when `status: "fail"`. |
| `evidence` | array\<EvidenceItem\> | yes | May be empty only for a synthetic/no-media story. See §2. |

The **cross-run identity key** for hashing, baselining, and NEW/CHANGED detection is
`feature + "\u0000" + title` — the two exact strings joined by a **NUL byte**,
not by a space, and not `id`. This matches the reference generator byte-for-byte: all five
places `build-review-report.mjs` builds this key (story map, accept hashing, scoped accept,
and the report JS's localStorage `keyFor()`) join with NUL — a deliberate delimiter no
feature name or behavior sentence can contain. A space-joined key would silently miss every
baseline lookup for a migrating project and spuriously flag 100% of its stories NEW.
Implementations should construct the delimiter at runtime (e.g. `String.fromCharCode(0)`)
rather than embedding a raw NUL byte in source. `id` never substitutes for this key.

**Persistence warning (field lesson 2026-07-08):** these NUL-joined keys appear as object
keys inside `baseline.reviewState.scenarios`, and several stores reject NUL bytes anywhere
in stored text — Postgres jsonb/text among them. A server that persists submitted baselines
verbatim will 500 on the first run a migrating-or-accepted project submits. Encode the keys
at the persistence boundary (a documented sentinel no feature/title can contain) and decode
at every read site; the wire format and in-memory semantics never change.
(Corrected 2026-07-06: an earlier draft of this section said space-joined — that was wrong,
caught by byte-level verification against the generator's real output.)

**Fields the client never sends, because the service derives them:** `isNew`, `isChanged`,
`proposed`, `nostory`, `unspecified`. These are badge-relevant but computed server-side —
`isNew`/`isChanged` from `spec` + `baseline.reviewState.scenarios` hash comparison (§1.5),
`proposed` from the behavior's own `status` in `spec`, `nostory`/`unspecified` from
structurally cross-referencing `spec` against submitted stories. **`status` and `isEdge`
are the entirety of the client-supplied badge-relevant flags.**

`done` (the behavior's completion conditions) is likewise never resubmitted per story — the
service reads it from `spec[feature].behaviors[title].done` for hash computation (§1.5).

### 1.5 Content hash (server-computed, not submitted)

For every story that resolves against an agreed behavior (and, for UNSPECIFIED stories, so
a later `accept` can baseline them once specified), the service computes:

```
contentHash = sha256(JSON.stringify({
  title,
  captions: evidence.filter(e => e.type !== 'video')
                    .map(e => e.caption),    // in submitted order
  done,                                      // from spec[feature].behaviors[title].done
  seeds
})).hex.slice(0, 16)
```

This generalizes the generator's rule — "title + captions + done conditions + seed
annotations" (`SKILL.md` §6, `contentHash`/`buildModel` in `build-review-report.mjs`) —
from "screenshot captions" to "every evidence item's caption, in submitted order," because
background stories narrate through timelines/artifacts/state-diffs the way UI stories
narrate through screenshots. **`video` captions are excluded from the hash — this is a
kit-parity requirement, not a style choice**: the existing generator hashes screenshot
captions only and never a recording's caption, so a UI story submitted by a migrating
kit-era client (screenshots + video, same order) MUST produce a byte-identical hash here —
otherwise every migrated project would flag every story CHANGED on its first run, a mass
false positive that teaches the owner to distrust the CHANGED badge. Background evidence
types are new (no installed base), so their captions join the hash without any
compatibility cost. **The broadening beyond screenshots is this document's
interpretation** — flagged in the closing summary.

Hash drift vs. `baseline.reviewState.scenarios[key]` ⇒ CHANGED, exactly as today.

---

## 2. Evidence vocabulary

Every evidence item shares an envelope, then adds type-specific fields:

```json
{
  "type": "screenshot",
  "caption": "string, required, owner-language",
  "attachments": [
    { "sha256": "<hex64>", "filename": "checkout-1.png", "contentType": "image/png", "role": "primary", "sizeBytes": 48213 }
  ],
  "metadata": { "timestamp": "2026-07-06T18:30:00.000Z", "origin": "e2e-runner" },
  "truncation": null
}
```

General rules (`SERVICE-DESIGN.md` §4, carried over unchanged):

- **Two faces**: every item has a readable **render** (what the report displays) and
  accessible **primary material** (download/inspect: the file, the row, the payload). For
  UI evidence (screenshot/video) the two coincide — the image/recording *is* the material.
  For background evidence they separate: the caption/render is presentation, the
  attachment(s) are the auditable ground truth.
- **Declared truncation, never silent**: whenever an item shows a subset of a larger set
  ("50 of 12,000 rows"), `truncation: { shown, total }` MUST be present. The service
  renders whatever the client declares, always visibly — it does not compute truncation
  itself.
- **Sensitive primary material**: deterministic/synthetic fixtures remain the doctrine;
  per-project redaction for what can't be synthetic is a v1 non-goal (tracks the deferred
  multi-tenant/auth decision, `SERVICE-DESIGN.md` §6).
- Caption language is the project's configured owner-language, free text — same convention
  as today's `STRINGS`-driven captions. The service validates presence, not language.

Every original video master is stored regardless of a story's NEW/CHANGED status (enabling
retroactive re-transcode across the whole catalog, `SERVICE-DESIGN.md` §9). The kit's
media-scoping rule ("only NEW/CHANGED/failing/PROPOSED/UNSPECIFIED stories embed media")
therefore applies **only to the self-contained HTML export format**, never as an ingest-time
restriction — the manifest always carries evidence for every story that has any. **This
scoping-is-export-only reading is this document's interpretation**, not a literal statement
in either source.

### 2.1 `screenshot`

| Field | Required | Constraint |
|---|---|---|
| `attachments` | exactly 1 | `role: "primary"`, `contentType: "image/png"` (PNG only — the kit's opaque-fixture, decode/paint-gated capture doctrine assumes lossless raster, `SKILL.md` §7). |

Render: full image in a lightbox-gallery convention (prev/next, position indicator);
**never displayed above its natural width**. Render and primary material coincide.

### 2.2 `video`

| Field | Required | Constraint |
|---|---|---|
| `attachments` | exactly 1 | `role: "primary"`. `contentType` one of the native-capture set (`video/webm`, `video/mp4`, `video/quicktime`), or already-valid H.264 in a compatible container. |

The uploaded file is the **original capture**; the service transcodes it server-side to the
canonical H.264 ladder (`SERVICE-DESIGN.md` §9 decision — media encoding is server-side);
already-valid H.264 passes through with no re-encode. `attachments[0].sha256` always refers
to the **original upload**, never a server-generated rendition — renditions are a serving
concern, not part of the evidence identity. Render: native `<video controls>`, poster from
first frame, a playback-speed bar, never displayed above encoded width; GIF is the fallback
render only when no H.264 rendition exists.

### 2.3 `timeline`

| Field | Required | Constraint |
|---|---|---|
| `events` | yes | Inline array `[{ "timestamp": "ISO 8601", "label": "string" }]` — the rendered narrative (e.g. "order arrived" → "worker picked it up" → "email sent"). Kept inline (small, textual) rather than blob-addressed. |
| `attachments` | ≥1 | `role: "records"` — the raw captured event records backing `events`; the primary material. |

Render: a real-timestamp sequence, per `SERVICE-DESIGN.md` §4's example. `events` is the
render; `attachments` is the audit trail — the two-faces separation made explicit.

### 2.4 `state-diff`

| Field | Required | Constraint |
|---|---|---|
| `attachments` | exactly 2 | `role: "before"` and `role: "after"` — both captured states (e.g. a row, serialized as JSON, before and after). |
| `metadata.resource` | recommended, optional | Free-text label of what changed, e.g. `"orders row id=42"`. |

Render: before/after comparison; the service may compute a text/JSON diff view when both
sides are structured/textual, otherwise offers both sides for side-by-side download.

### 2.5 `artifact`

| Field | Required | Constraint |
|---|---|---|
| `attachments` | 1–2 | The real file the job produced (`.eml`, PDF, CSV, a webhook payload). A request/response pair uses two attachments, `role: "request"` / `role: "response"`; otherwise one, `role: "primary"`. |

Render: previewable inline when `contentType` supports it (PDF, image, CSV table);
otherwise a labeled download. No format allowlist beyond an accurate `contentType`.

### 2.6 `log-excerpt`

| Field | Required | Constraint |
|---|---|---|
| `attachments` | exactly 1 | `role: "primary"`, the raw excerpt (typically `text/plain`). |
| `truncation` | required whenever excerpt ≠ full log | See the general rule above — this is the type truncation exists for. |

Render: collapsed, annotated detail — by doctrine never the sole/primary evidence for a
story's verdict on its own. The service cannot mechanically enforce this (it cannot judge
evidentiary sufficiency); it is a capture-contract expectation (§6.2), not a validation rule.

### 2.7 `metric`

| Field | Required | Constraint |
|---|---|---|
| `value` | yes | number |
| `unit` | no | string, e.g. `"ms"`, `"count"` |
| `provenance` | yes | string — where the number came from |
| `attachments` | no | Metrics are usually just the numbers + provenance text; like UI evidence, render and primary material coincide here — no file required. |

---

## 3. Blob protocol

**Content-addressed by sha256**: every blob is keyed by the hex digest of its raw bytes.
Dedup is scoped **per project** (not global) — this avoids one project's existence-check
leaking whether another project has ever uploaded a byte-identical file, a cross-tenant
inference risk not worth the marginal storage savings of global dedup. This scoping choice
is this document's own addition, not sourced from either input document.

### 3.1 Hash-first dedup handshake

1. Client computes the sha256 of every local file it intends to attach.
2. Client asks the service which of those hashes it already has (scoped to `projectId`).
3. Client uploads only the missing ones — raw bytes over plain HTTP, never through the
   MCP/LLM channel (`SERVICE-DESIGN.md` §3).
4. The manifest's evidence `attachments` then reference all hashes — newly uploaded or
   already known — never local paths (§4.1 covers how the agent-facing tool differs).

Illustrative operations (exact routing is a service implementation detail, not fixed by
this contract):

- **Blob check** — request `{ projectId, hashes: string[] }` → response `{ missing: string[] }`.
- **Blob upload** — raw body = file bytes, addressed by the target hash; the service
  re-hashes on receipt and rejects on mismatch against the declared hash (§6.1).

### 3.2 Accepted upload formats

Per the decision log (`SERVICE-DESIGN.md` §9):

| Evidence | Accepted | Handling |
|---|---|---|
| Video | Native capture containers `.webm`, `.mp4`, `.mov` | Transcoded server-side to the canonical H.264 ladder. |
| Video | Already-valid H.264 | Passes through with no re-encode. |
| Screenshot | `.png` only | Stored as-is. |
| Other evidence types | Any `contentType` accurately declared | No allowlist — artifact/log-excerpt/timeline/state-diff material is inherently open-ended. |

Anything outside a type's allowed set is rejected at ingest (§6.1).

### 3.3 Size limits (defaults — all **TUNABLE**)

| Scope | Default cap |
|---|---|
| Screenshot (PNG) | 5 MB |
| Video (raw upload, pre-transcode) | 500 MB |
| Artifact file | 100 MB |
| Timeline / state-diff / log-excerpt raw material | 20 MB |
| Manifest JSON body (excluding blobs) | 5 MB |
| Total blobs per run | 2 GB |

### 3.4 Server-side transcode guarantee

Every video blob gets (or already satisfies) the canonical H.264 ladder; **media is never
displayed above its encoded width** — unchanged kit doctrine (`SKILL.md` §6), now a service
guarantee instead of something each client's local ffmpeg had to get right.

---

## 4. MCP tool surface

Five tools ("the 4+1"): `submit_run`, `get_run`, `wait_for_verdict`, `accept` (folds in the
kit's `--accept-only` as a parameter), `get_history`.

### 4.1 `submit_run`

The agent-facing input differs from the wire-level manifest (§1) in exactly one respect:
each evidence attachment carries a **local file path** instead of a blob hash — the model
never moves bytes (`SERVICE-DESIGN.md` §3). The local thin client resolves path → hash →
dedup-check → upload (§3) → substitutes the real `sha256`, then forwards a §1-shaped
manifest to the service. That substitution is the only structural difference; every other
field is identical to §1.

**Input**

| Field | Type | Notes |
|---|---|---|
| `manifest` | object | §1 shape, except each evidence attachment carries `localPath` instead of `sha256`. |

**Output**

| Field | Type | Notes |
|---|---|---|
| `runId` | string | |
| `reviewUrl` | string | Hosted review UI link (`SERVICE-DESIGN.md` §5). |
| `counts` | object | `{ total, pass, fail, new, changed, proposed, noStory, unspecified, happy, edge }` — same tally the generator's model computes today. |
| `ratchet` | object | `{ ok: boolean, regressions: [{ metric, previous, current }] }`, computed against `baseline.metricsHistory`'s last row, non-null-in-both only (§7 freeze item 6). **Informational, not a hard reject** — enforcement stays the client pipeline's job upstream (`SKILL.md` §2: "the gates upstream should make it unreachable"); the service additionally surfaces the same check for visibility, since `SERVICE-DESIGN.md` §2 assigns "metrics ratchet" to the service side. This response shape and the non-blocking choice are this document's own design, not literally specified in either source. |

### 4.2 `get_run`

Input: `{ runId }`. Output: `{ state, counts, reviewUrl }`.

| `state` | Meaning |
|---|---|
| `processing` | Ingest/transcode in flight. |
| `ready` | Report generated, awaiting owner review. |
| `verdict_in_progress` | Owner has marked at least one item in the hosted UI. |
| `verdict_complete` | Owner explicitly finished the review. |

`verdict_complete` is reached by an **explicit owner action** in the hosted UI, not inferred
from "zero unmarked" — `SIN MARCAR` can legitimately stay nonzero if the owner deliberately
defers an item, so auto-detecting completion from it would be unreliable. This inference
rule is this document's own addition; neither source defines the state-machine trigger.

### 4.3 `wait_for_verdict`

Input: `{ runId, timeoutMs }`. Long-polls server-side up to `timeoutMs`.

```json
{
  "status": "verdict_complete",
  "verdict": [
    { "feature": "Bienvenida", "title": "la persona ve un mensaje de bienvenida al abrir la app", "state": "bien", "note": "" }
  ],
  "generatedAt": "2026-07-06T19:00:00.000Z"
}
```

`status` is `"verdict_complete"` or `"timeout"` — `verdict` is **always** the current
snapshot of marks (not `null` on timeout), so a client can show interim progress before
retrying. Each `verdict[]` entry: `{ feature, title, state, note }`, where `state` ∈
`bien | falla | unmarked` — untranslated keys, unchanged from the generator (§5).

### 4.4 `accept`

Folds the kit's `--accept` / `--accept-only` into one tool via an optional `scope`.

**Input**: `{ runId, scope?: string[] }` — omitted/empty `scope` ⇒ wholesale accept
(`doAccept`); non-empty ⇒ scoped accept (`doAcceptOnly`), rejecting with an
unknown-feature error if any name isn't in this run's `spec` (mirrors the generator's
`ERROR: --accept-only: funcionalidad(es) desconocida(s)…`).

**Semantics preserved exactly** (`SKILL.md` §6, `doAccept`/`doAcceptOnly`):

- Wholesale: baselines every story hash in the current run (**all** features in `spec`,
  reviewed or not) and flips every `"proposed"` behavior to `"approved"`. Overwrites
  `reviewState` wholesale.
- Scoped: baselines/flips **only** the named features, **merging** into the prior
  `reviewState` — every other feature's baseline is preserved untouched, never replaced.
  Exists so a partial review round never silently baselines (and drops next-run media for)
  stories the owner hasn't reviewed.
- Either form appends one `metricsHistory` row, **idempotent** on identical run content
  (same `runContentHash` key as `buildHistoryRow`) — a cosmetic republish never
  double-appends.

**Output** — the updated baseline content for the client to write back and commit to git:

```json
{
  "reviewState": { "acceptedAt": "2026-07-06T19:05:00.000Z", "features": ["Bienvenida"], "scenarios": { "Bienvenida ...": "a1b2c3d4e5f60718" } },
  "metricsHistory": [ { "acceptedAt": "2026-07-06T19:05:00.000Z", "runContentHash": "..." } ],
  "spec": { "Bienvenida": { "behaviors": { "...": { "status": "approved" } } } },
  "flippedCount": 1
}
```

v1 `accept` is **agent-invoked via MCP only** — mirrors the kit's CLI flags exactly.
"Accept-from-hosted-UI" (owner accepts where they review) is the explicit alternative
`SERVICE-DESIGN.md` §6 leaves open and defers; not implemented in v1.

### 4.5 `get_history`

Input: `{ projectId }`. Output: `{ rows: metricsHistory }` — same row shape as §1.3.

**Ratchet contract**: compare a metric only when it is non-null in **both** the row being
checked and the row before it; null on either side is skipped — never coerced to 0, never
treated as a regression (verbatim from `SKILL.md` §2's never-regress ratchet, unchanged).

---

## 5. Verdict shape

Per-story verdict state uses the generator's own **untranslated data keys** — contract-level
tokens, never localized (`build-review-report.mjs`: `NEXT_STATE`, `STATE_LABEL`,
`computeSummary`):

| Key | UI label (owner-language, presentation only) |
|---|---|
| `unmarked` | "Sin marcar" |
| `bien` | "✓ Bien" |
| `falla` | "✗ Falla" |

Cycle: `unmarked → bien → falla → unmarked`. Each mark carries an optional `note` (free
text; the kit's UI caps it at 200 characters — a UI convention, not a wire-level limit this
contract mandates). A note may exist even on an otherwise-`unmarked` item.

`verdict[]` item shape (§4.3): `{ feature, title, state, note }` — `feature` + `title` is
the same identity key as §1.4/§1.5 (exact string match), not `id`.

**Note update semantics (presence-based — field lesson 2026-07-08):** when a verdict-mark
submission item does NOT carry the `note` property at all, the stored note is left
untouched; an explicit `note: null` clears it; a string sets it. Implementations must use a
property-presence check, never `item.note ?? null` — the coalescing form silently erases a
saved note the moment the owner later taps BIEN/FALLA (whose mark payloads naturally omit
`note`), which is exactly the bug this rule exists to prevent.

### 5.1 Export-parity requirement

Whatever the service returns as structured verdict JSON MUST be renderable, byte-for-byte,
into the same plain-text export the kit already produces — so any agent that already parses
that pasted text parses the service's output unchanged. Algorithm, verbatim from
`buildVerdict()`:

```
VEREDICTO DEL REPORTE — <generatedAt>
BIEN (<n>):
- <feature> :: <title>
   ...one line per item where state === "bien"...
FALLA (<n>):
- <feature> :: <title>[ — nota: <note>]
   ...one line per item where state === "falla"; the " — nota: " suffix appears only
   when note is non-empty...
NOTAS (<n>):
- <feature> :: <title> — <note>
   ...one line per item carrying a non-empty note, REGARDLESS OF STATE — this can repeat
   a line already listed under FALLA...
SIN MARCAR: <n>
```

`n` for `SIN MARCAR` counts only **attention** items (badges ∈ `{fail, new, changed,
proposed, nostory, unspecified}`) still `unmarked` — not every unmarked item in the report;
an unmarked, already-approved-unchanged story never counts here. This is a precise,
easy-to-miss rule, reproduced exactly from `computeSummary()` / `isAttentionBadge()`.

---

## 6. Ingest validation

### 6.1 The service rejects

| Rejection | Detail |
|---|---|
| Missing blobs | An evidence attachment's `sha256` was never uploaded (dedup-check said missing, upload never followed, or upload failed). Response lists exactly which hashes. |
| Hash mismatch | Uploaded bytes' actual sha256 ≠ the declared hash. |
| Unknown evidence type | `type` outside `{screenshot, video, timeline, state-diff, artifact, log-excerpt, metric}`. |
| Wrong attachment shape for type | Cardinality/role/contentType violations from §2 (e.g. a `state-diff` with one attachment, a `screenshot` that isn't `image/png`, a video container outside the accepted set). |
| Manifest schema violations | Missing required fields, wrong types, `contractVersion` absent or unsupported major (§7), a story's `feature` not a key in `spec` at all, duplicate `id` within a run. |
| `accept` scope violation | `scope` names a feature absent from this run's `spec` (§4.4). |

### 6.2 The client's capture duty (out of scope for server validation in v1)

The service cannot reach into the client's app, database, or filesystem
(`SERVICE-DESIGN.md` §2) — if a story didn't capture something at run time, it doesn't
exist as evidence, and the service has no way to know what was *missed*. This is the
**capture-contract**, carried unchanged from `SKILL.md` §7, and it stays entirely
client-side in v1 (no evidence-QA/LLM layer — `SERVICE-DESIGN.md` §7, deprioritized):

- Pacing: recordings must breathe (slowMo ~400–500ms at record time; playback speed cannot
  fix a skipped state).
- Decode/paint gates before every snap (image `naturalWidth`/decode, painted-pixel checks
  for canvases).
- Scrolling the asserted element into frame before its snap.
- Opaque test fixtures (a transparent 1×1 PNG "passes" while showing nothing).
- Caption honesty: a caption may never claim what the pixels don't show.
- Seed annotations must be run-stable (no unique IDs baked in) — otherwise the server
  reports spurious CHANGED on every run, through no fault of its own hashing logic (§1.5).

The service validates **shape**; it cannot and does not validate **visual truth**.

---

## 7. Versioning

- `contractVersion` (e.g. `"1.0"`) is required on every manifest (§1).
- Semver-ish: **additive, backward-compatible changes bump MINOR** (a new evidence `type`,
  a new optional field, a new metric key) — a service on a given major MUST accept a
  manifest declaring a newer-or-equal minor within that major and ignore fields it doesn't
  yet recognize. **Any change to a frozen item below is MAJOR** and requires an explicit,
  versioned migration on both sides — never silent drift.

### v1 freeze list — what can never change silently

1. Badge tokens (English, contract-level, never localized): `pass, fail, happy, edge, new,
   changed, proposed, nostory, unspecified`.
2. Verdict state tokens: `bien, falla, unmarked`, and their cycle order.
3. Verdict export structure/labels: `VEREDICTO DEL REPORTE — `, `BIEN (`, `FALLA (`,
   `NOTAS (`, `SIN MARCAR: `, the `- <feature> :: <title>` line shape, and the
   NOTAS-includes-any-noted-item rule (§5.1).
4. Content-hash recipe: sha256 of `{title, captions (ordered, video captions excluded for
   kit parity), done, seeds}`, hex, first 16 characters (§1.5).
5. Accept semantics: wholesale accept baselines the **entire** current run and flips
   **every** proposed behavior; scoped accept **merges** into the prior baseline and flips
   **only** named features — never a silent replace of unrelated features.
6. Never-regress ratchet null-handling: compare a metric only when non-null in **both**
   rows; null on either side is always skipped, never coerced to 0, never a regression.
7. "Attention" badge set for `SIN MARCAR` accounting: `fail, new, changed, proposed,
   nostory, unspecified` (excludes approved-unchanged).

### Explicitly out of scope for v1 (not part of this contract)

- Database/API-surface manifest sections (`SKILL.md` §6, points 4–5) — not requested here,
  not addressed by the service design's evidence vocabulary.
- Multi-tenant auth, retention windows, redaction configuration (`SERVICE-DESIGN.md` §6,
  open decisions).
- The LLM layer (`SERVICE-DESIGN.md` §7 — deprioritized, built last).
- Accept-from-hosted-UI (`SERVICE-DESIGN.md` §6 — left open, not adopted here).
