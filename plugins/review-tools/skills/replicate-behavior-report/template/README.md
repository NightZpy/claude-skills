# Report generator template

`build-review-report.mjs` is the standard starting point for the behavior-report generator:
copy it into your repo (e.g. `test/behavior/build-review-report.mjs`), fill in the
`// ===== CONFIG (adapt per project) =====` block near the top, and run it. Don't re-author
this file from the SKILL.md §6 prose — **SKILL.md §6 is the CONTRACT this file implements**
(badges, verdict format, media scoping, accept semantics). Redesign the HTML/CSS/JS freely;
keep the contract.

Field-tested provenance: this generator shipped in production, where a real,
non-technical, Spanish-speaking user base reviewed real features through it. No license header; copy and adapt freely.

## Smoke-run (no real suite needed)

```bash
node build-review-report.mjs --config sample
```

This points the generator at `sample-data/` instead of your repo's `test/behavior/` — a
minimal fixture set (one feature, two behaviors: one with a passing story, one with none) —
and writes the report to `sample-data/.out/review-report.html`. Use it to confirm the
generator itself works before you've wired up a real Playwright suite or `features.json`.
The sample has no video attachment, so it also demonstrates the generator degrading
honestly when a story has no recording to embed (no crash, no broken media block).

## What to adapt

Everything you need to touch lives in the CONFIG block:

- **`PRODUCT_NAME`** — interpolated into the report's title and a couple of metric labels.
- **Paths** — `E2E_DIR`, `RESULTS_JSON`, `FEATURES_JSON`, `REVIEW_STATE`, `METRICS_HISTORY`,
  `OUTPUT_HTML`, `DATA_DIR` (optional `metrics.json`/`hygiene.json`). Defaults assume this file
  lives at `test/behavior/build-review-report.mjs` relative to your repo root.
- **`STRINGS`** — every owner-facing string the report renders, in one object. The Spanish
  copy shipped here is field-tested; swap the whole object to translate. There is no other
  hardcoded copy in the file — every render function reads from `STRINGS`.

Everything else (badge model, media scoping, size ladders, the mark/verdict mechanics, the
`--accept` / `--accept-only` flows) is the contract from SKILL.md §6 and should not need to
change per project — only per genuine design decision, made deliberately.

## Files

```
build-review-report.mjs   the generator — copy this
sample-data/               minimal fixture set for --config sample
  features.json             1 feature, 2 behaviors (one with a story, one without)
  results.json               matching Playwright-JSON-reporter-shaped run (1 passed spec)
  media/snap1.png, snap2.png  tiny fixture screenshots referenced by results.json
```
