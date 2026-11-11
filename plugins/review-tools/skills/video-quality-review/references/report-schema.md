# Output schemas

Three files. `vqr.py check` validates the first and the third; the second is
free-form within the shape below.

## `report.json` — one per video

```json
{
  "schema": "vqr-report/1",
  "label": "V1",
  "video": {"sha256": "…", "duration_s": 183.47, "width": 1080, "height": 1920},
  "request": {"topic": "…", "language": "es", "aspect": "9:16", "duration_s": [90, 180],
              "safe_zone": "text ≥ 320 px above the bottom edge", "subtitles_expected": false},
  "reviewer": {"judge": "sonnet", "runner": "haiku", "describer": "haiku"},
  "audio_playback": "none — offline measures only",
  "transcript": {"source": "own", "engine": "mlx_whisper large-v3-turbo",
                 "subtitle_source": "unknown", "subtitle_accuracy": "NOT SCORED — no subtitles",
                 "refilled_windows": 2},
  "passes": {
    "A1": {"kind": "audio", "tools": "loudnorm+envelope+ASR", "resolution_s": 0.1},
    "M1": {"kind": "mechanical-video", "fps": 30, "window": "full", "resolution_s": 0.033},
    "P1": {"kind": "frames", "fps": 0.5, "window": "full", "resolution_s": 2.0, "frames": 92},
    "P2": {"kind": "frames", "fps": 2, "window": "0-5s", "resolution_s": 0.5, "frames": 10},
    "P3": {"kind": "frames", "fps": 4, "window": "14 cuts ±1s", "resolution_s": 0.25, "frames": 112},
    "P4": {"kind": "zoom", "window": "9 crops", "resolution_s": 0.25}
  },
  "verdict": "SHIP WITH FIXES",
  "levels": {"D1": "Rough", "D2": "Clean", "D3": "Distracting", "D4": "Distracting",
             "D5": "Clean", "D6": "NOT SCORED — no subtitles outside the embedded clip"},
  "level_basis": {"D1": "F01", "D2": "G02", "D3": "F02 F03", "D4": "F01", "D5": "G01", "D6": "-"},
  "findings": [
    {"id": "F02", "dim": "D3", "class": "flicker", "severity": 3,
     "f": "recurring", "i": "attention", "p_s": 12,
     "t": [65.33, 66.1], "pass": "M1", "region": "top-left,top-center,top-right",
     "kind": "measured", "confidence": "high", "verified_by_judge": true,
     "evidence": "two document cards are fully visible at M1@01:05.20; the left one is gone at M1@01:05.33 and fades back by M1@01:05.70, then the right one does the same; 21 more re-entry events of the same shape at other scene starts (mechanical.json visual.flashes)",
     "expected": "an element animates in once, from absent",
     "fix": {"formulable": true, "action": "hide", "what": "each document card",
             "t": [65.2, 65.7], "region": "top-left,top-center,top-right",
             "target": "absent from the first frame of the scene until its own entrance starts; enters once",
             "verify": "measure: no visual.flashes event in [65.2, 66.2]"}}
  ],
  "positives": [
    {"id": "G01", "dim": "D5", "t": "full", "pass": "P1", "kind": "judged",
     "evidence": "all 14 source captures are legible at delivery size and carry a source line"}
  ],
  "requirements": [
    {"requirement": "official logos of the three models, synced with their mentions",
     "status": "met", "evidence": ["G03"]},
    {"requirement": "natural pronunciation of the narration",
     "status": "not-evaluable", "evidence": [], "note": "subjective listening not performed"}
  ],
  "not_scored": ["prosody, pronunciation, music-vs-voice mix — subjective listening not performed",
                 "external factual truth — no sources",
                 "identity consistency — no identifiable subject"],
  "coverage": {"frames_described": 214, "frames_read_by_judge": 31,
               "candidates": {"flashes": 35, "reappearances": 1, "align_early_late": 3},
               "dropped": ["P3: 1 of 15 hard cuts not sampled (budget)"],
               "blind_spots": ["a wrong label that appears and clears inside a P1 gap away from a cut"]},
  "escalate": []
}
```

Rules `check` enforces:

- `audio_playback` starts with `none`; `not_scored` has an entry containing
  "listening".
- Every pass has `resolution_s`. Every `levels.D1..D6` is `Clean`, `Rough`,
  `Distracting`, `Broken` or starts with `NOT SCORED`.
- Every finding has all the fields above. `pass` is **one** declared pass. `t`
  is `[start, end]` in seconds, at least as wide as that pass's resolution.
- Clock times in `evidence`/`expected` are written `PASS@MM:SS` or
  `PASS@MM:SS.d`. Decimal durations ("0.4s") must not be finer than a fifth of
  the pass's resolution.
- `severity` 1–4. `i: cosmetic` cannot be above S2. S4 needs
  `i: comprehension|trust` and `s4_reason` ∈ `fabricated-claim`,
  `gibberish-as-information`, `wrong-identity`, `unintelligible-narration`,
  `d1-gate`. S3/S4 need `verified_by_judge: true` and cannot be
  `confidence: low`.
- `fix` is present on every finding: either `formulable: false` with a `why`,
  or `formulable: true` with `action` (from the fixed verb list), `what`, `t`
  `[start, end]`, `region`, `target` and a `verify` that starts with
  `measure:`, `align:`, `probe:` or `listen:`. A decimal number of seconds in
  `what`/`target` must not be finer than a fifth of the finding's pass
  resolution. Optional `condition`.
- `region` uses the 3×3 names (comma-separated for several), `full-frame` or
  `audio`; add `in-safe`/`out-safe` when it applies.
- `verdict` equals the one derived from the findings. 2–5 positives. Every id
  in `escalate` exists.

Warnings (not failures): a dimension at `Clean`/`Rough` holding an S3+; an S4
missing from `escalate`.

Not checked, still required: `class` from the vocabulary in SKILL.md;
`level_basis` naming the finding or positive behind each level; no model,
provider, profile or cost anywhere in the file.

## `notes.json` — written by `vqr.py notes report.json --out notes.json`

```json
{"schema": "vqr-notes/1", "label": "V1",
 "notes": [
   {"finding": "F02", "t": [65.2, 65.7], "type": "hide", "region": "top-left,top-center,top-right",
    "severity": 3, "class": "flicker",
    "note": "each document card → absent from the first frame of the scene until its own entrance starts; enters once",
    "verify": "measure: no visual.flashes event in [65.2, 66.2]"}
 ],
 "cannot_be_written_from_the_video": [
   {"finding": "F06", "t": [112.0, 114.0], "class": "number-mismatch",
    "why": "the screen says 35 and the voice says 53; which is right needs the source figure"}
 ]}
```

One note per formulable fix, sorted by `t`. `type` is the fix's `action`;
mapping it onto a panel's own note types is the caller's.

## `calibration.json` — only after `report.json` is frozen

```json
{
  "schema": "vqr-calibration/1",
  "label": "V1",
  "frozen_report_sha256": "…",
  "feedback_source": "owner chat, 2026-11-11",
  "statements": [
    {"quote": "tiene unos resaltados que parecen parpadeos", "outcome": "hit", "findings": ["F02"]},
    {"quote": "los subtítulos están mal en el vídeo meme, desincronizados", "outcome": "miss",
     "reason": "not-sampled", "note": "no subtitle probe was placed inside the clip"},
    {"quote": "la música de fondo es monótona", "outcome": "not-perceivable-offline"},
    {"quote": "yo habría elegido un estilo más dinámico", "outcome": "preference"}
  ],
  "recall": 0.5,
  "unmentioned_s3_plus": ["F05"],
  "late_findings": [
    {"class": "sub-desync", "t": [9.0, 9.5], "pass": "P4", "kind": "measured",
     "evidence": "…", "found": "after reading the feedback — not part of the blind verdict"}
  ],
  "lessons_for_next_video": ["place subtitle probes inside every embedded clip"]
}
```

`outcome` ∈ `hit`, `miss`, `not-perceivable-offline`, `preference`. `reason`
(for a miss) ∈ `not-sampled`, `seen-not-flagged`, `below-threshold`,
`no-check-for-it`. `recall` counts hits and misses only.

## `family.json` — written by `vqr.py compare`, completed by the judge

`compare` fills `videos` (label, verdict, levels, counts, classes, finding ids,
measured numbers, the report's sha256), `same_audio`, `class_matrix`,
`ordering` and `ordering_rule`. The judge appends to `differences`:

```json
{"statement": "V2 replays entrance animations at 9 scene starts; V1 at none",
 "videos": ["V1", "V2"], "evidence": ["V2:F02", "table:flash_events"],
 "kind": "measured", "confidence": "high", "decides_ordering": true}
```

`check` requires `statement`, at least two `videos`, `kind`, `confidence`, and
every `evidence` entry to be `LABEL:FINDING_ID` of a listed report or
`table:<column>`.
