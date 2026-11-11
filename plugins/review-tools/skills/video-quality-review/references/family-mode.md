# Family mode — N videos from the same request

Use it when several videos answer one request: the same brief given to
different generators, profiles or versions. The output is one `report.json` per
video, plus `family.json` and a summary.

**1 · Label blind.** `V1..Vn` from the caller, or by sorting sha256. Copy or
link each file to `<out>/<label>/video.mp4` so that no later step sees a
telling filename. Nothing about who or what made each video enters any report.

**2 · One plan for all.** Same passes, cadences, caps, thresholds, prompts and
`vqr.py`. `compare` warns if the declared passes differ between reports. A
video that got a denser look will show more defects, and that difference is
yours, not the video's.

**3 · One fresh judge per video.** Steps 0–9 of SKILL.md run per video in a separate
context (one subagent each), and each `report.json` is frozen before any
comparing starts. A judge that has seen V1 grades V2 against V1 instead of
against the rubric.

**4 · Compare (R, then J).**

```bash
$VQR compare <out>/V1 <out>/V2 <out>/V3 --out <out>/family.json
```

It prints the table (verdict, levels, severity counts, S3+ per minute,
duration, loudness, cuts per minute, flicker events), the computed ordering —
**ties stay ties** — the defect classes not shared by all, and `same_audio`:
pairs whose level envelopes match. Videos built on one shared voice track
differ only in the picture; any D2 difference between them is noise, and their
timestamps line up, which makes step 5 below exact.

**5 · Side by side (R, then D and J).** One row per video, the same moments:

```bash
$VQR strip <out>/side_open.jpg "V1=<out>/V1/video.mp4@0.5,1.5,2.5,4" "V2=<out>/V2/video.mp4@0.5,1.5,2.5,4"
```

Always: the opening, the ending, and three to five beats of the request. With
shared audio, use the same timestamps. Without it, find each video's own time
for the same sentence or idea in its transcript — a strip that lines up
different moments compares nothing.

**6 · Differences (J).** Add to `family.json` → `differences`, each one:

```json
{"statement": "V2 opens on the subject within the first second; V1 holds a title card for 4 s",
 "videos": ["V1", "V2"], "evidence": ["V1:F02", "V2:G01"],
 "kind": "judged", "confidence": "high"}
```

- Evidence is `LABEL:FINDING_ID` from the frozen reports, or `table:<column>`.
  A difference with nothing behind it on one side is not a difference yet — go
  back, look at that video at that beat, and add what you saw as an addendum.
- **Absence needs coverage.** "V1 has no flicker" is a claim only because M1
  covered every frame. "V1 has no overlap" needs the same beats sampled in
  both.
- Counts compare per minute, and only within the cohort rule.
- Say which differences decide the ordering and which are taste. Do not break a
  tie the table left tied; say what a person would have to weigh.

Then `$VQR check <out>/family.json`. If the caller also declares an order among
the videos (v1 → v2), add per class: `fixed`, `persisting`, `new` — matched by
class and content, never by timestamp.

**Family summary:** the table · the ordering · five to ten differences, most
decisive first · what was not comparable and why.
