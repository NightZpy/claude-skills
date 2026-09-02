---
name: video-quality-review
description: >
  Use when reviewing a finished generated video for quality — invoked with a
  video path or URL, or on phrases like "revisa este video", "review this
  video", "qué tal quedó el video". Judges the video AS A VIDEO: what a viewer
  sees and hears. Runs an audio pass and four frame passes at cadences chosen by
  the rubric (never by asking the user), scores six dimensions with anchored
  levels, and emits severity-tagged findings that each carry a time interval, a
  screen region, and verbatim evidence. Accepts an optional transcript to skip
  re-transcribing. Deliberately blind to the generator's internals — it never
  reads logs, prompts, configuration or database rows, and never explains a
  defect by its cause.
---

# Video Quality Review

Turn a finished video into a defect report a person can act on: **what is wrong,
where exactly, how bad, and with the evidence quoted**.

The emphasis is on defects. But every report also records what worked — without
that, there is no way to tell whether the next video regressed.

## The boundary — read this before anything else

You judge the video **as a viewer experiences it**. Your inputs are the video
file and the request that produced it (topic, requested language, duration,
aspect ratio) — plus, optionally, a transcript (see below).

**You never read the generator's own records**: its logs, prompts, scene plan,
model configuration, database rows, or observability stack. Not even to check a
hunch.

**You never explain a defect by its cause.** "The director planned the scene
around the wrong narration window" is forbidden. "The heading says TRES FINALES
while the narration at that moment is about the player's age" is the finding.
You report symptoms with evidence; someone else diagnoses.

Why this is a hard rule and not a preference: a reviewer that can see the plan
stops looking at the picture and starts grading the plan. The defects that reach
viewers are precisely the ones the plan does not predict.

You **may** run any tool on the file itself — `ffmpeg`, `ffprobe`, ASR, frame
extraction, OCR. The file is the video, not an internal.

## The transcript — the one question you ask

A caller who generated the video usually already has a transcript with word
timings. Take it: re-transcribing costs time and money for something that
already exists.

But **one check cannot use it**, and the reason is not obvious.

If the burned-in subtitles were rendered *from* that transcript — which is the
normal case — then checking the subtitles against it is circular. It compares
the text against the text it came from. It will always pass. And the defect it
exists to catch is exactly the one it would certify: a transcript that
hallucinated words nobody spoke, faithfully burned into the picture.

Independent verification requires an independent transcript. There is no way
around that.

So ask, once, before starting:

> **Do you want to verify that the subtitles match what is actually said?**
> Yes → I transcribe the audio myself (slower, costs an ASR run).
> No → I use the transcript you gave me and skip that check.

- **Yes** → produce your own transcript with an engine of a **different family**
  from the one that made the subtitles. Subtitle accuracy is `measured`. If you
  can only run the same family, say so and downgrade it to `judged` with the
  note *"same-family ASR; shared hallucination possible"*.
- **No** → use the supplied transcript. Subtitle accuracy is
  `NOT SCORED — transcript not independent`. Say it in the report; do not quietly
  return green.

This is the **only** question you ask. Cadence, scope and sampling are the
rubric's decisions, never the user's — see §5. This one is different because it
is a cost and coverage trade-off, which is the caller's to make.

**Everything else the transcript feeds is unaffected**, because none of it is
circular: word timings drive the mid-word cut check (D3) and the
narration-versus-picture alignment (D4). Cuts are decided by the assembler and
pictures by the scene plan — neither comes from the transcript, so comparing
against it is a real comparison. Use the supplied transcript for those in both
branches.

## The six dimensions

| ID | Dimension | Kind |
|---|---|---|
| **D1** | Hook & delivered intent | Judged + 3 binary gates |
| **D2** | Audio & narration | Measured core; judgmental residue NOT SCORED |
| **D3** | Edit & motion timing | Measured core + judged residue |
| **D4** | Narration ↔ visual correspondence | Judged + 1 measured sub-check |
| **D5** | Visual integrity | Judged |
| **D6** | Subtitles & on-screen text mechanics | Measured |

### Every finding is tagged `measured` or `judged`

`measured` = a threshold was compared against a number you produced. No
discretion was involved.
`judged` = you looked and formed an opinion, however well-evidenced.

The word is mandatory on every finding. It is the mechanical form of the rule
that matters most here: **never state a judgement with the false confidence of a
measurement.**

### Measured sub-checks

**D1 gates** (any failure is automatically S4):
- Spoken language is the requested language.
- Aspect ratio is 9:16.
- Duration within ±10% of requested.

**D2:**
- Integrated loudness in [−18, −14] LUFS, true peak ≤ −1 dBTP (`ffmpeg
  -af loudnorm=print_format=json`). *The target is chosen by us, not a platform
  citation — no primary TikTok/Reels LUFS spec was found. Say so if you cite it.*
- No silent gap > 1.5s in the middle of narration.

**D3:**
- **No cut inside a spoken word.** Cut times from scene detection, word
  intervals from your own ASR. "Inside" = the cut falls within
  `[word_start + 50ms, word_end − 50ms]`.
- **Animation reveal check.** For each animation segment, diff the first sampled
  frame against the last. Visually identical ⇒ the reveal finished before the
  segment was on screen. No judgement needed.

**D4:**
- On-screen number (OCR) vs narrated number (ASR): exact diff. Two numbers are
  equal or they are not.
- The same value+heading pair appearing twice within one graphic.

**D6:**
- Burned subtitle text vs independent ASR, verbatim diff. **See the ASR
  collusion rule below — this is only `measured` under a condition.**
- Sync offset ≤ 250ms, to your sampling resolution.
- Placement inside the union safe zone (use the Reels box: 1010×1280 within
  1080×1920 — it has the largest bottom margin, and we do not know the target
  platform).
- Worst-frame contrast behind the text ≥ 4.5:1. Worst frame, not average: the
  background moves.
- Reading speed ≤ 17 CPS. *Chosen by us inside the BBC (15) – Amazon (20)
  range. Not a universal constant.*

## Anchored levels

Four levels, shared names, per-dimension text: **Clean / Rough / Distracting /
Broken**. Four and not five, deliberately — an even count has no middle to
default into, and the middle is where "everything is basically fine" hides.

### D1 — Hook & delivered intent
- **Clean** — the first sampled frame already shows the subject or an image
  tied to it, and the first spoken sentence states or teases the specific
  promise of the request. The video then delivers it.
- **Rough** — the subject is clear within 3s, but the opening spends its first
  breath on throat-clearing (a title card, an establishing shot, a greeting)
  before any payoff. The promise arrives late or partially.
- **Distracting** — the first 3 seconds could open any video on this topic. No
  expectation set, no curiosity gap. Or the video answers a visibly different
  question than the one asked.
- **Broken** — the opening promises something the video never delivers, or the
  first frames are broken media: black, placeholder, wrong language.

### D3 — transitions & synthetic motion (judged residue)
- **Clean** — every transition matches its content event: hard cut on
  continuous flow, dissolve on a time or topic shift. Motion eases in and out
  and never pulls the eye off the content.
- **Rough** — one or two mismatched transitions, or motion slightly too fast or
  slow. All content still readable.
- **Distracting** — motion repeatedly competes with the content: a zoom
  outrunning reading speed, a dissolve landing mid-action, a visible stutter at
  cuts.
- **Broken** — motion defeats the content. Text leaves frame before it can be
  read; something strobes or lurches.

### D4 — narration ↔ visual correspondence
- **Clean** — at every sampled moment the screen illustrates the clause being
  spoken, and adds something the words do not say. On-screen figures equal
  narrated figures.
- **Rough** — neutral filler: on-topic but generic imagery under a specific
  claim. Nothing contradicts, nothing reinforces.
- **Distracting** — the screen illustrates a *different sentence* than the one
  being spoken. Right topic, wrong slot; or a graphic repeats or omits data in a
  way a reader would puzzle over.
- **Broken** — the image channel asserts something the narration does not, or
  contradicts it: a heading claiming a fact never spoken, a number that
  disagrees with the voice, a different subject presented as the subject. **The
  picture is lying.**

### D5 — visual integrity
- **Clean** — the subject is recognisable and consistent across scenes; embedded
  text is legible and orthographically real; sharpness holds through maximum
  zoom; the scenes read as one production.
- **Rough** — defects only a paused, hunting eye finds: soft edges at maximum
  zoom, off anatomy on background figures, mild palette drift with a plausible
  narrative reason.
- **Distracting** — visible at normal speed: a face that changes between scenes,
  garbled decorative text, one scene from a visibly different palette with no
  narrative reason.
- **Broken** — the subject is the wrong person or entity, or carries the
  identity markers of a rival or wrong entity, or readable text presented as
  information is gibberish. A knowledgeable viewer would call the video fake.

## Severity

Nielsen 0–4, with the decomposition mandatory. Every finding carries
`(f: once|recurring|throughout, i: cosmetic|attention|comprehension|trust,
p: <duration affected>)`, and the severity number must be consistent with them.
Writing `S4 (i:cosmetic)` is a self-contradiction and the report fails its own
check.

- **S1 cosmetic** — found only by hunting. Fix if free.
- **S2 minor** — a viewer notices. Attention and trust survive.
- **S3 major** — costs attention or causes momentary confusion. Fix next time.
- **S4 critical** — destroys trust or comprehension.

**S4 has a fixed membership list.** Nothing else is S4:
- A false or fabricated claim in any channel — a hallucinated subtitle
  asserting content, a contradictory visual, a wrong on-screen number.
- Readable gibberish presented as information.
- Wrong subject or identity.
- Unintelligible narration.
- Any D1 binary gate failure.

**Verdict:**

| | condition |
|---|---|
| **DO NOT SHIP** | ≥1 S4, **or** ≥3 S3 across distinct dimensions |
| **SHIP WITH FIXES** | any S3 |
| **SHIP** | otherwise |

One S4 overrides every Clean level in the report. That is the entire reason
severity lives outside the dimension scores.

## Honest precision — the mechanism

Sampling frames every second gives **0% temporal-detection accuracy** in
measured studies (>95% at 20–30 fps, 59% at 10 fps, 0% at 1 fps). A reviewer
that samples sparsely and then cites a frame number is inventing.

This is not a warning. Warnings get ignored. It is three rules and a checker:

**1. Declare every pass in a machine-readable header**, before any finding:

```
P1 {fps:0.5, window:full}
P2 {fps:2, window:0-5s}
P3 {fps:4, window:cuts±1s + animation head/tail}
P4 {zoom, driven by P1/P3 hedges}
A1 {channel:audio, tools:loudnorm+ASR(<engine name>), resolution:0.1s}
```

**2. Every finding names the pass it came from, and its precision is inherited
from that pass.** An audio finding may cite 0.1s. A P1 finding may not cite
anything finer than 2s. Ever.

**3. Onsets are intervals, never instants:**
`t=[last-clean-sample – first-affected-sample]`, e.g. `t=[00:14.0–00:16.0] P1`.

**Prerequisite:** frames must be named by their real timestamp
(`window_start + i/fps`, or ffmpeg's `-frame_pts`). Naming frames by index and
calling the index a timestamp makes rule 2 impossible to honour.

**The checker.** Before delivering, verify every finding's cited precision
against its pass's resolution. A finding finer than its pass is a defect *in the
report* — fix it or drop it. Do not deliver a report that fails this.

## Output format

One parseable line per finding:

```
F07 | D4 | S4 (f:once i:trust p:6s) | t=[00:31.0–00:33.0] P1 | region=center,in-safe | judged | seen: heading "TRES FINALES" over stat graphic (frame 00:32.0) while ASR 00:29.8–00:36.5 = "…tenía 35 años…"; "tres finales" is spoken at 00:25.1 | expected: the graphic matches the clause in its own slot
```

Fields, in order: id · dimension · severity(f/i/p) · time interval + pass ·
region · `measured|judged` · evidence · expected.

**Region** uses the rule-of-thirds 3×3 vocabulary — `top-left`, `top-center`,
`top-right`, `center-left`, `center`, `center-right`, `bottom-left`,
`bottom-center`, `bottom-right` — composed with `in-safe` / `out-safe`. "The
subtitle is `bottom-right` and `out-safe`" is a stronger statement than either
half alone.

**Evidence quotes verbatim.** For D4, quote both channels. A paraphrase is not
evidence.

**Positives are findings too**, same shape, `G`-prefixed. **Two to five per
report, mandatory** — they are the regression baseline:

```
G01 | D6 | t=[full] A1+P1 | measured | all 41 subtitle events matched the independent ASR verbatim
```

**Report structure:** header (passes, ASR engine, video hash, duration) →
verdict → scoreboard row → findings → positives.

The scoreboard row is the cross-video comparison unit:
`verdict | D1..D6 levels | S4/S3/S2/S1 counts per dimension | NOT-SCORED list`.

**Cohort rule:** levels and verdicts compare across any two videos. Raw counts
and ratios only compare within the same duration and preset class.

## How to run it

### A1 — audio pass, always first

Cheapest and it tells the frame passes where to look. Produces: loudness,
independent ASR with word timings, scene-cut times, animation segment bounds.
Feeds D2, D3's cut check, D4/D6 text alignment.

### Frame passes, via `video-frame-review`

That skill is the frame-evidence engine: extract → describe with a cheap
describer subagent → zoom or densify where evidence is hedged. Use it, with four
changes:

1. **No interaction.** It normally asks the user for scope via
   `AskUserQuestion`. Here the rubric chooses the cadence — pass an explicit
   plan and skip the question entirely.
2. **Real timestamps in frame names** (the prerequisite above).
3. **Fixed watch-list.** The describer reports, for every frame: burned subtitle
   text verbatim, any on-screen numbers and headings verbatim, the subject's
   face and wardrobe, and a sharpness note.
4. **The describer never sees the ASR text.** D4 is judged by aligning two
   *independently produced* streams. A describer that has been shown the
   narration will see content that matches it.

Keep its `[unreadable]` discipline — a hedge is the trigger to zoom, never
something to accept as the answer.

### Default cadence

Densify freely. **Never go sparser than this.**

| pass | cadence | serves |
|---|---|---|
| **A1** | audio only | D2, D3 cuts, D4/D6 alignment |
| **P1** | fps=0.5, full video | D5 baseline, D4 sampling, subtitle OCR seed |
| **P2** | fps=2, 0–5s | D1 — dense, because the opening is what decides everything |
| **P3** | fps=4, ±1s around every cut + first/last second of every animation | D3 |
| **P4** | targeted zooms on text-bearing regions | D4/D5/D6 |

P3 is the expensive one and it earns it: cuts landing mid-word and animations
that finish before they are seen exist **only** in those windows. Most
dimensions do not need dense sampling — D2 needs no frames at all.

Roughly 200 describer frames for a 90-second video.

## Where this rubric fails — read before trusting a green report

**ASR collusion.** If your ASR is the same family as the one that produced the
subtitles, it can hallucinate the *same* text that was burned into the picture,
and D6 will certify a hallucination as verbatim-correct: measured, green, wrong.
Same-family models fail in the same places — that is what makes the agreement
worthless as evidence.

> **Rule:** D6 accuracy is `measured` only when your engine is a different
> family from the one that made the subtitles. Same family → downgrade to
> `judged` with the note *"same-family ASR; shared hallucination possible"*.
> Supplied transcript → `NOT SCORED` (see the transcript section). The engine
> declared in your header is what makes this checkable at all.

**D1 is the most pattern-matched dimension.** It is easy to grade a hook by
formula — "opens with a question, therefore strong" — from the transcript alone,
without looking at anything.

> **Rule:** a D1 level is invalid unless it quotes both the first-frame visual
> content (from P2) and the first spoken words (from A1), with timestamps. No
> citations, no score.

**Refuse to score what you cannot perceive.** Mark it `NOT SCORED — <missing
capability>` and keep the marker stable across videos so comparability survives:

- **Prosody, pronunciation, music-vs-voice mix** — you do not hear audio.
  Proxying this from a transcript is guessing.
- **External factual truth** — you have no sources. D4 covers only *internal*
  contradiction between channels. "The claim is false" is not yours to make;
  "the screen and the voice disagree" is.
- **Actual retention** — you have no audience. The hook level is a craft
  judgement and must never be phrased as a retention measurement.
- **Ken Burns naturalness outside densified windows** — motion inferred from two
  sparse stills is not observed motion.

**Accepted blind spot.** A defect that appears and fully resolves inside a P1
2-second gap, away from any cut, will be missed. The alternative is
dense-sampling everything, which the cadence plan exists to avoid. The
mitigation is that real defects cluster at cuts, openings and text — which is
exactly where the dense passes sit. Say this in the report rather than implying
full coverage.

## What this rubric deliberately does not cover

Three things the previous rubric scored are **out of scope here**, because they
need exactly the database and log access this reviewer is denied:

- Whether the output matches the configuration that was requested of the
  generator, beyond the three gates in D1.
- Pipeline integrity.
- Cost and efficiency.

They are not worthless — they belong to an automated audit that runs *beside*
this review, not inside it.

One piece of the previous rubric is not merely dropped but **contradicted**: the
guidance to watch at normal speed and only dig where something jars. A model
reviewer cannot watch at normal speed, and sparse sampling is not a cheaper
version of looking — at 1 fps it is not looking at all. The cadence plan
replaces it.
