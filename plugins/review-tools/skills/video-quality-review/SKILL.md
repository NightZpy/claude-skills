---
name: video-quality-review
description: >
  Use when reviewing a finished generated video for quality — invoked with a
  video path or URL, or on phrases like "revisa este video", "review this
  video", "qué tal quedó el video" — or when comparing a FAMILY of videos made
  from the same request. Judges the video AS A VIDEO: what a viewer sees and
  hears. Runs an offline audio pass (never played through speakers), a
  native-frame-rate mechanical pass (flicker, reappearing screens, chopped clip
  edges) and four frame passes at cadences chosen by the rubric, scores six
  dimensions with anchored levels, and emits findings that each carry a time
  interval, a screen region, verbatim evidence, a confidence level and a
  checkable video-level fix — as stable JSON, a short summary and time-coded
  correction notes. Calibrates against owner feedback only after the blind
  report is frozen. Written for a Sonnet judge with Haiku runners. Blind to the
  generator's internals: never reads logs, prompts, configuration or costs,
  and never explains a defect by its cause.
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

**You do say how to fix it — in the video's own terms.** "Hide the chapter card
between 00:12 and 00:18" is a statement about the picture: anyone can check it
on the next render without knowing how the video is built. "Fix the scene's
start offset" is a diagnosis in disguise — forbidden, and useless to whoever
uses a different tool. See "Every finding carries a fix".

**The request can leak, and can anchor.** A brief often names tools, ids and
file names — ignore them; they are internals that happen to be written down. A
request that is itself a list of corrections to an earlier version is still the
request: it says what was asked, and each item becomes a row in
`requirements`. But its defects belong to *that* version. Find defects in this
video's pixels first; never copy one in from the list.

Two extensions of the same boundary:

- **Who made it is an internal.** Model, provider, profile, version, cost and
  run time are the generator's records. If a path or a brief leaks one, do not
  use it and do not repeat it; refer to videos by neutral label (`V1`, `V2`).
  "V2 is worse because the cheaper profile made it" is a cause — forbidden.
- **The owner's feedback is not an internal, but it is sealed.** It is a
  viewer's reaction, so you may read it — only *after* your own report is
  frozen (see "Calibration"). Read first, and you grade the feedback instead of
  the video.

## Never play the audio

**No sound ever leaves this machine's speakers.** Not `open`, QuickTime,
`afplay`, `ffplay`, a browser tab, or an ffmpeg output to an audio device. The
review runs unattended on a machine someone is sitting next to, and a model
gains nothing from a loudspeaker — it cannot hear one.

Audio is examined offline only — decoded to a pipe, a file or `-f null`:
loudness, true peak, the level envelope, digital-silence holes, level steps at
cuts, and ASR. `scripts/vqr.py` has no code path to an audio device; use it
rather than improvising ffmpeg audio commands.

Every report carries `"audio_playback": "none — offline measures only"` and
lists under NOT SCORED: *"prosody, pronunciation, music-vs-voice mix —
subjective listening not performed"*. A transcript and a LUFS number do not
show that a voice sounds natural or that a clip is intelligible to a person.

## What the caller hands over

| input | required | note |
|---|---|---|
| video file(s) | yes | one video, or a **family**: N videos made from the same request |
| the request | yes | topic, language, aspect ratio, duration or range, and any viewer-visible requirement (safe zone, "no subtitles", "logos when named") |
| neutral labels | family | `V1..Vn`. If none are given, assign them by sorting the files' sha256 — never by filename |
| transcript | no | see below |
| `subtitle_source` | no | what made the burned-in subtitles: `script` / `asr:<engine>` / `unknown`. You cannot find this out yourself — it is an internal — and the collusion rule needs it |
| `verify_subtitles` | no | `yes` / `no`: the answer to the one question below, given up front |
| owner feedback | no | a path, **not opened until the report is frozen** |

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
  note *"same-family ASR; shared hallucination possible"*. Which family made
  the subtitles is the caller's `subtitle_source`: `script` means no ASR was
  involved, so any engine of yours is independent; `unknown` counts as the
  same family.
- **No** → use the supplied transcript. Subtitle accuracy is
  `NOT SCORED — transcript not independent`. Say it in the report; do not quietly
  return green.

This is the **only** question you ask. Cadence, scope and sampling are the
rubric's decisions, never the user's — see "Default cadence". This one is
different because it is a cost and coverage trade-off, which is the caller's
to make.

Ask it **once per run** — once for a whole family, not once per video. If the
caller already passed `verify_subtitles`, do not ask. If the caller supplied no
transcript, there is nothing to ask: transcribe. If nobody can answer (you
are a subagent, or a batch job): default to **yes** when `vqr.py doctor` shows a
local ASR engine — the run then costs compute, not money — and to **no**
otherwise. Write the branch you took in the report's `transcript` block.

**Everything else the transcript feeds is unaffected**, because none of it is
circular: word timings drive the audio-edge check at cuts (D3) and the
narration-versus-picture alignment (D4). Cuts are decided by the assembler and
pictures by the scene plan — neither comes from the transcript, so comparing
against it is a real comparison. Use the supplied transcript for those in both
branches.

## The six dimensions

| ID | Dimension | Kind |
|---|---|---|
| **D1** | Hook & delivered intent | Judged + 3 binary gates |
| **D2** | Audio & narration | Measured core; judgmental residue NOT SCORED |
| **D3** | Edit, motion timing & pacing | Measured core + judged residue |
| **D4** | Narration ↔ visual correspondence | Judged + measured sub-checks |
| **D5** | Visual integrity | Judged |
| **D6** | Subtitles & on-screen text mechanics | Measured |

### Every finding is tagged `measured` or `judged`

`measured` = either of:
- a threshold was compared against a number you produced, no discretion
  involved, **or**
- two genuinely independent instruments read the same thing and agreed,
  with no discretion used to decide what either one reported (e.g. a
  vision describer and an OCR engine both transcribe the same garbled
  string the same way).

`judged` = you looked and formed an opinion, however well-evidenced.

This widens `measured` rather than adding a third tag — the tag vocabulary on
a finding line stays two words, and agreement between independent instruments
removes exactly the same discretion a threshold comparison does: what
happened is no longer a matter of interpretation.

**Independence is the whole test.** Two runs of the *same* model or engine are
not independent — they fail in the same places, which is exactly why the ASR
collusion rule below (§"Where this rubric fails") downgrades same-family ASR
agreement to `judged`. Before tagging a corroborated finding `measured`, be
able to name why the two instruments are independent (different model
family, different technique — vision model vs. OCR, not two calls to the
same vision model).

The word is mandatory on every finding. It is the mechanical form of the rule
that matters most here: **never state a judgement with the false confidence of a
measurement.**

**A candidate from `vqr.py measure` is not yet a finding.** The script reports
that pixels or samples changed; whether that is a defect needs eyes. Once the
frames in its strip have been read and they show what the numbers say, the two
instruments — pixel arithmetic and a vision model — are independent and agree,
so the finding is `measured`. If the frames were not read, there is no finding.

### Every finding carries a confidence

`measured|judged` says how the fact was established. `confidence` says how far
to trust the *finding* — fact, defect-or-intended, and severity together.

| | condition |
|---|---|
| **high** | `measured` and plainly a defect; or `judged` on frames the judge read personally, seen in ≥2 samples, with no plausible reading in which it is intended |
| **medium** | `judged` on frames the judge read, but from one sample, or intent is arguable (a stylistic choice could explain it) |
| **low** | rests on a describer's text nobody verified, on a proxy (ASR confidence standing in for audibility), or on a candidate whose strip was inconclusive |

**Low confidence caps severity at S2** and the finding goes in `escalate`. A
defect you are unsure about is reported as unsure — not dropped, and not
promoted.

### Measured sub-checks

**D1 gates** (any failure is automatically S4):
- Spoken language is the requested language.
- Aspect ratio is the requested one (16:9 explainers and 9:16 shorts are both
  normal — the gate is the request, not a house format).
- Duration within ±10% of a requested target. When the request gives a range or
  a maximum instead, that is the gate, with no tolerance — stated limits are
  usually a platform's.

**D2:**
- Integrated loudness in [−18, −14] LUFS, true peak ≤ −1 dBTP (`ffmpeg
  -af loudnorm=print_format=json`; `audio.integrated_lufs` and
  `audio.true_peak_dbtp` in `mechanical.json`). *The target is chosen by us, not a platform
  citation — no primary TikTok/Reels LUFS spec was found. Say so if you cite it.*
- No silent gap > 1.5s in the middle of narration (`audio.dead_air`,
  `audio.speech_gaps` with `as_loud_as_speech: false`).
- No hole in a continuous bed: when `audio.continuous_bed` is true, any
  mid-video `dead_air` run (≥0.15s of digital silence) is a dropout.

A gap in the *transcript* is not silence. `speech_gaps` with
`as_loud_as_speech: true` is music, another language, or an ASR dropout — look
at what is on screen before calling it anything.

**D3:**
- **No audio chopped at a cut.** `audio.cuts[]` gives, per hard cut, the level
  step across it and the words on either side. A finding needs **both**: a
  hard audio edge (`|step_db| ≥ 20`) **and** `said_before`/`said_after` showing
  a word or sentence broken there. A picture cut while the narration simply
  carries on is ordinary editing — `inside_word` alone is not a finding (ASR
  word starts are early by up to ~0.2s; on a real video 13 of 15 clean cuts
  "fell inside a word").
- **No flicker.** `visual.flashes[]`, sampled at the native frame rate:
  `flash` (the picture jumps away and is back within 0.2s), `blink` (≤0.5s),
  `re-entry` (an element already on screen vanishes and eases back in — the
  entrance replayed over its own end state). Read the strip, then apply the
  candidate table below.
- **No screen shown twice by accident.** `visual.reappearances[]`: a screen,
  something else, the same screen again.
- **No stray blank frames.** `visual.blank_frames[]` with `position: middle`
  and `hard_edges: true`. (`hard_edges: false` is a fade through black.)
- **Animation reveal check.** For each animation segment, diff the first sampled
  frame against the last. Visually identical ⇒ the reveal finished before the
  segment was on screen. No judgement needed.

**D4:**
- **On-screen text vs the moment it is spoken.** `vqr.py align` takes the
  describer's on-screen text timeline and the transcript and reports each text
  as `in-slot`, `early`, `late` (with the offset and both quotes) or
  `never-spoken`. The offset is measured; whether it is a defect is the
  candidate table's call.
- On-screen number (OCR) vs narrated number (ASR): exact diff. Two numbers are
  equal or they are not.
- The same value+heading pair appearing twice within one graphic.

**D6:**
- Burned subtitle text vs independent ASR, verbatim diff. **See the ASR
  collusion rule below — this is only `measured` under a condition.**
- Sync offset ≤ 250ms, to your sampling resolution. ASR word starts run up to
  ~0.2s early, so with 0.25s probes an offset is `measured` only from 0.5s up;
  between 0.25s and 0.5s it is `judged`, `confidence: medium`.
- Placement inside the safe zone. The request's own safe zone wins when it
  states one. Otherwise, 9:16: the Reels box, 1010×1280 within 1080×1920 — it
  has the largest bottom margin, and we do not know the target platform. 16:9:
  the inner 90% (5% margins) — *chosen by us*.
- Worst-frame contrast behind the text ≥ 4.5:1. Worst frame, not average: the
  background moves.
- Reading speed ≤ 17 CPS. *Chosen by us inside the BBC (15) – Amazon (20)
  range. Not a universal constant.* It applies to any on-screen sentence, not
  only subtitles.

A video with no subtitles scores D6 on its other on-screen text; subtitle
accuracy and sync are `NOT SCORED — no subtitles`. Whether subtitles were
*wanted* is the request's business, and goes in `requirements`.

## From candidate to finding — the rules that keep this from being naive

`vqr.py` is deliberately trigger-happy: it lists everything that *could* be a
defect. Most intended things look like defects to arithmetic — a still
background, a fade through black, a drama cutting back to the same face. Each
candidate becomes a finding only through this table, after the judge has read
its strip.

| candidate | it is a finding when | it is **not** when | class |
|---|---|---|---|
| `flash` | the strip shows a wrong image, a blank or a misplaced element for a few frames | the whole video uses a strobe/glitch look on purpose | `flicker` |
| `re-entry` | an element is fully visible, vanishes, and animates back to the same state | what comes back is different content (a counter ticking, one caption replacing another) | `flicker` — several scenes doing it is `f:recurring` |
| `blink` | something appears and is gone before it can be read | — | `flicker` |
| blank frame, `middle` + `hard_edges` | always worth a finding | `hard_edges: false`: a fade through black | `blank-frame` |
| `reappearances` | a title, section card or text screen that was already presented comes back and the narration there is not returning to it — above all right after an inserted clip (`first` ends where the clip starts, `again` starts where it ends) | a scene cutting back to a speaker or place; a recap the narration announces; a base layer (a map, a board) the section keeps building on | `screen-reappears` |
| `holds` ≥ 2s inside an embedded clip | the clip's picture stands still while its own sound runs on | a clip that is a still image by nature | `frozen-picture` |
| `holds` ≥ 8s | the narration keeps going (words inside the hold) and nothing at all changes on screen | a deliberate still: a suspense beat, a document held to be read, a look the request asks for. **A static background is never a defect by itself** | `pacing-slow` |
| `speech_gaps`, not loud, ≥1.5s, mid-video | the picture is not carrying the moment either | a visual beat that is clearly meant to play without voice | `dead-air` |
| `dead_air` under a continuous bed | always (measured) | — | `audio-hole` |
| cut with `|step_db| ≥ 20` | `said_before`/`said_after` show a broken word or sentence, or a clip that starts from silence into running action | a new section starting on a sentence boundary | `hard-clip-entry`, `hard-clip-exit`, `cut-in-word` |
| `low_confidence_speech` | it sits inside an embedded clip whose words matter: the machine could not make them out | proper nouns and brand names | `asr-unintelligible` — always `confidence: low`, with "a person must listen; if they cannot make it out either, cut the clip" |
| `orphan_bursts` | a sound with no word under it, after speech has ended | — | `orphan-audio` — `confidence: low` |
| `align` `early`/`late` ≥ 3s | the frame *presents* that text as its subject while the quoted narration is on something else | persistent chrome (logo, channel tag, source note, a section header that stays up); an agenda that previews on purpose; anticipation ≤ 2s | `out-of-slot` |
| `align` `never-spoken` | a label with no function, or a claim the voice never makes | text that adds what the words do not say — that is what D4 `Clean` asks for | `stray-label`, or D4 `Broken` if it asserts a fact |

A screen shown twice is **one** finding, `screen-reappears`, not also an
`out-of-slot`: cite the `align` row in its evidence, and put the fix on
whichever showing `align` leaves out of slot. `weak-match` rows in `align` (one
shared word out of several) are not candidates at all. A `never-spoken` proper
noun is usually the ASR spelling it by ear — look for the sound-alike in the
transcript before believing it.

### Defect classes

Every finding names one. The vocabulary is fixed so that two videos, two
reviewers and the owner's feedback can be matched without interpretation.

| dim | classes |
|---|---|
| D1 | `gate-language` `gate-aspect` `gate-duration` `weak-hook` `undelivered-promise` |
| D2 | `loudness` `true-peak` `dead-air` `audio-hole` `orphan-audio` `asr-unintelligible` |
| D3 | `flicker` `blank-frame` `screen-reappears` `frozen-picture` `hard-clip-entry` `hard-clip-exit` `cut-in-word` `reveal-done-early` `transition-mismatch` `pacing-slow` `pacing-rushed` |
| D4 | `out-of-slot` `stray-label` `number-mismatch` `contradiction` `filler` `duplicate-data` |
| D5 | `layer-out-of-slot` `occluded-subject` `overlap` `text-clipped` `text-illegible` `artifact-shape` `gibberish-text` `identity` `style-break` `empty-space` `unrequested-chrome` |
| D6 | `sub-desync` `sub-mismatch` `sub-out-safe` `sub-contrast` `sub-speed` `sub-overlap` |

The D5 ones nobody can measure, and they are the ones owners report most.
They are the describer's watch-list (step 4):

- `layer-out-of-slot` — something from the previous or the next scene is
  visible in this one: a leftover title, a card under another card.
- `occluded-subject` — a panel, band or shape covers the image or background
  the scene is about.
- `overlap` — two texts, or a text and a graphic, on top of each other.
- `text-clipped` — a word cut by the frame edge or by its own box.
- `text-illegible` — too small, too low-contrast, or gone too fast. A text the
  describer could only read after a zoom is illegible to a viewer on a phone.
- `artifact-shape` — a disc, plate, bar or box with no function.
- `empty-space` — a large dead area while the content is crammed elsewhere.
- `unrequested-chrome` — progress bars, slide counters, disclaimer banners the
  request did not ask for. Never above S2.

## Every finding carries a fix

A finding says what is wrong; its `fix` says what the next render must look or
sound like, precisely enough that someone can make the edit and someone else
can check it. It is written at the level of the video — what, when, where, to
what value — never at the level of the generator.

```json
"fix": {"formulable": true, "action": "hide",
        "what": "the chapter card \"PARTE DOS\"",
        "t": [12.0, 18.0], "region": "center",
        "target": "not shown before the inserted clip; first appears at 01:02, where the voice reaches it",
        "verify": "measure: no visual.reappearances pair for this screen · align: \"PARTE DOS\" in-slot"}
```

`action` is one verb from a fixed list (`hide`, `remove`, `retime`, `trim`,
`fade`, `move`, `resize`, `restyle`, `replace`, `add`, `level`). `what` names
the thing as a viewer would point at it — never a layer, track, scene id or
file. `t` and `region` are where the *edit* applies. `target` is the value to
reach, no finer than the pass that measured it ("0.25–0.5s earlier", not
"0.3s"). `verify` names the check to re-run on the new file and starts with
`measure:`, `align:`, `probe:` or `listen:`. An optional `condition` makes the
fix depend on something only a person can establish.

**Read `references/fix-recipes.md` at step 9, before writing the first `fix`**
— it defines each field and gives the recipe for every defect class.

**When the video alone cannot dictate the fix, say so:**

```json
"fix": {"formulable": false,
        "why": "the screen says 35 and the voice says 53; which is right needs the source figure"}
```

That covers: which of two disagreeing channels is right; what a garbled thing
was meant to say; material the video does not contain; a whole-piece redo. An
invented fix sends someone to change the right thing to the wrong value —
worse than an honest gap. `why` names exactly what is missing.

**Correction notes.** `vqr.py notes report.json --out notes.json` turns the
fixes into one note per finding — `t`, `type` (the action), `region`, `note`,
`verify`, plus `condition` when there is one — sorted by time, ready to send to
a review panel that takes notes by time, type and frame zone. Findings with
`formulable: false` are listed apart, with their `why`, and produce no note.

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

### D2 and D6 — measured dimensions
No prose to interpret: the level follows the worst finding in the dimension.
- **Clean** — every measured sub-check passes, or S1 only.
- **Rough** — an S2.
- **Distracting** — an S3, or an S2 that recurs.
- **Broken** — an S4: narration that cannot be understood, a subtitle
  asserting words nobody said.

### D3 — transitions & synthetic motion (judged residue)
- **Clean** — every transition matches its content event: hard cut on
  continuous flow, dissolve on a time or topic shift. Motion eases in and out
  and never pulls the eye off the content.
- **Rough** — one or two mismatched transitions, or motion slightly too fast or
  slow, or one stretch that outstays its content. All content still readable.
- **Distracting** — motion repeatedly competes with the content: a zoom
  outrunning reading speed, a dissolve landing mid-action, a visible stutter at
  cuts, elements that flicker as scenes open, a clip that starts or ends
  chopped. Or the pace sags: the voice moves on while the screen does not, more
  than once.
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
  narrative reason; or layout that gets in the way — texts overlapping, a word
  cut off, a shape over the subject, information too small to read.
- **Broken** — the subject is the wrong person or entity, or carries the
  identity markers of a rival or wrong entity, or readable text presented as
  information is gibberish. A knowledgeable viewer would call the video fake.

> **A `Clean` earned with an identifiable subject and a `Clean` earned without
> one are not the same result.** Half of what D5 detects is identity — a wrong
> face, a rival's crest, a shirt number that changes. Material with no
> identifiable subject (objects, places, data) has no identity to contradict, so
> that half cannot fail. Report it as `NOT SCORED — no identifiable subject` for
> the identity component and score the rest normally; see "Refuse to score what
> you cannot perceive" below.

## Severity

Nielsen 0–4, with the decomposition mandatory. Every finding carries
`(f: once|recurring|throughout, i: cosmetic|attention|comprehension|trust,
p: <duration affected>)`, and the severity number must be consistent with them.
Writing `S4 (i:cosmetic)` is a self-contradiction and the report fails its own
check.

| `i` | usual severity | goes one higher when |
|---|---|---|
| `cosmetic` | S1 | `f: recurring/throughout` → S2 (never above) |
| `attention` | S2 | `f: recurring/throughout`, or it affects more than a tenth of the video → S3 |
| `comprehension` | S3 | it is on the S4 list below |
| `trust` | S3 | it is on the S4 list below |

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

**The border test for "a contradictory visual":** it is S4 when a viewer who
simply believes the screen comes away with a claim that neither the voice nor
the request makes. If the false reading needs interpreting — a line that could
mean two things, a legend that does not match its drawing — it is S3, and it
goes in `escalate`.

**Verdict:**

| | condition |
|---|---|
| **DO NOT SHIP** | ≥1 S4, **or** ≥3 S3 across distinct dimensions |
| **SHIP WITH FIXES** | any S3 |
| **SHIP** | otherwise |

One S4 overrides every Clean level in the report. That is the entire reason
severity lives outside the dimension scores.

**The verdict is computed, not chosen.** `vqr.py check` derives it from the
findings with this table and rejects a report that states another. An S4 also
needs an `s4_reason` naming its entry in the membership list, and every S4 goes
in `escalate`.

## Honest precision — the mechanism

Sampling frames every second gives **0% temporal-detection accuracy** in
measured studies (>95% at 20–30 fps, 59% at 10 fps, 0% at 1 fps). A reviewer
that samples sparsely and then cites a frame number is inventing.

This is not a warning. Warnings get ignored. It is three rules and a checker:

**1. Declare every pass in a machine-readable header**, before any finding:

```
A1 {channel:audio, tools:loudnorm+envelope+ASR(<engine name>), resolution:0.1s}
M1 {mechanical, fps:native, window:full, resolution:1 frame}
P1 {fps:0.5, window:full}
P2 {fps:2, window:0-5s}
P3 {fps:4, window:cuts±1s + animation head/tail}
P4 {zoom, driven by P1/P3 hedges}
```

`M1` is `vqr.py measure`: every frame, compared to its neighbours at thumbnail
size. It sees *that* something changed and where, to the frame — never *what*.
Its reappearance check runs at 2 samples per second, so those intervals are
0.5s wide (`reappearance_resolution_s`).

**2. Every finding names the pass that located it — one label — and its
precision is inherited from that pass.** An audio finding may cite 0.1s. An M1
finding may cite a frame. A P1 finding may not cite anything finer than 2s.
Ever.

A finding often needs a second pass as a witness: a P1 frame against an A1
quote. Cite the witness with its own label — `A1@00:29.8` — and it carries its
own pass's precision, not the finding's. An untagged clock time in the prose is
a defect in the report.

**3. Onsets are intervals, never instants:**
`t=[last-clean-sample – first-affected-sample]`, e.g. `t=[00:14.0–00:16.0] P1`.

A defect that happens many times is **one** finding with `f: recurring`: `t` is
its clearest instance, and `occurrences` lists the others as `[start, end]`
pairs. Do not stretch `t` over the whole video — that claims a 3-minute defect.

**Prerequisite:** frames must be named by their real timestamp.
`vqr.py frames`, `sheet` and `strip` do this: each frame is fetched by seeking
to its time, the file name is that time (`p1_t0083.00.jpg` = 01:23.00) and
every tile has it stamped on. If you extract with ffmpeg's `fps` filter
instead, the time is `window_start + (i - 0.5)/fps` for a 1-indexed `i` — the
filter samples the *midpoint* of each interval, measured and detailed in
`video-frame-review`'s "Frame timestamps run half an interval late". Naming
frames by index and calling the index a timestamp makes rule 2 impossible to
honour either way.

**The checker.** Before delivering the report, run this over every finding, in
order:

1. Read the finding's pass label (the token after the `t=[...]` interval,
   e.g. `P1`). Look up that pass's declared resolution from its header
   entry.
2. Scan the **whole finding line** — not just the `t=[...]` field — for any
   number that implies time precision finer than that resolution. This
   includes numbers inside the `evidence` and `expected` prose ("0.83s
   ahead", "3 frames later", "at 00:14.3"). A P1 finding (2s resolution) that
   says the interval right but then writes "0.83s ahead" in its evidence
   sentence still fails the checker — the violation lives in the prose, not
   the field, and a checker that only parses `t=[...]` will not catch it.
3. Any hit fails the check on that finding. Round the number to the pass's
   resolution, widen it back into an interval, or drop the claim it can't
   support. Do not deliver a report that still has one.

A finding finer than its pass is a defect *in the report* — fix it or drop it.

`vqr.py check` runs the mechanical part of this: interval no narrower than the
pass's resolution, every clock time in the prose tagged `PASS@`, and no decimal
number of seconds ("0.31s") unless it is a multiple of the pass's resolution or
has no more digits than a fifth of it — in a P4 finding at 0.25s, "0.25s" and
"0.5s" pass and "0.31s" does not. The same goes for `fix.target`. It does not read meaning — "three
frames later" in a P1 finding still gets past it, and is still yours to catch.

## Output format

Two artefacts per video, always both: **`report.json`** — the report itself,
stable and machine-checked — and a **summary of at most 15 lines** rendered
from it. The full schema with a worked example is in
`references/report-schema.md`; read it before writing your first report.

A finding in `report.json`:

```json
{"id": "F07", "dim": "D4", "class": "out-of-slot", "severity": 3,
 "f": "once", "i": "comprehension", "p_s": 6,
 "t": [31.0, 33.0], "pass": "P1", "region": "center,in-safe",
 "kind": "judged", "confidence": "high", "verified_by_judge": true,
 "evidence": "heading \"TRES FINALES\" over stat graphic (P1@00:32) while A1@00:29.8–A1@00:36.5 = \"…tenía 35 años…\"; \"tres finales\" is spoken at A1@00:25.1",
 "expected": "the graphic matches the clause in its own slot",
 "fix": {"formulable": true, "action": "retime", "what": "the heading \"TRES FINALES\"",
         "t": [24.0, 26.0], "region": "center",
         "target": "on screen only while A1@00:25.1 says it; gone before 00:30",
         "verify": "align: \"TRES FINALES\" in-slot"}}
```

and the same finding as one summary line:

```
F07 | D4 out-of-slot | S3 (f:once i:comprehension p:6s) | t=[00:31.0–00:33.0] P1 | region=center,in-safe | judged, high | seen: heading "TRES FINALES" over stat graphic (P1@00:32) while A1@00:29.8–A1@00:36.5 = "…tenía 35 años…"; "tres finales" is spoken at A1@00:25.1 | expected: the graphic matches the clause in its own slot | fix: retime the heading "TRES FINALES" → on screen only while A1@00:25.1 says it; gone before 00:30 (check: align in-slot)
```

Fields: id · dimension + class · severity(f/i/p) · time interval + pass ·
region · `measured|judged` + confidence · evidence · expected · fix.

**Region** uses the rule-of-thirds 3×3 vocabulary — `top-left`, `top-center`,
`top-right`, `center-left`, `center`, `center-right`, `bottom-left`,
`bottom-center`, `bottom-right` — composed with `in-safe` / `out-safe`. "The
subtitle is `bottom-right` and `out-safe`" is a stronger statement than either
half alone. `full-frame` when it is everywhere; `audio` for a finding with no
picture.

**Evidence quotes verbatim.** For D4, quote both channels. A paraphrase is not
evidence. Quote the transcript as the ASR wrote it, tagged `A1@`; its spelling
of a name ("Megaspid") is the engine's ear, never a finding.

**Positives are findings too**, `G`-prefixed. **Two to five per report,
mandatory** — they are the regression baseline:

```
G01 | D6 | t=[full] A1+P1 | measured | all 41 subtitle events matched the independent ASR verbatim
```

**Summary structure:** header (label, passes, ASR engine, video hash, duration,
`audio playback: none`) → verdict → scoreboard row → findings, worst first →
positives → NOT SCORED and coverage in one line each.

The scoreboard row is the cross-video comparison unit:
`verdict | D1..D6 levels | S4/S3/S2/S1 counts per dimension | NOT-SCORED list`.

**Cohort rule:** levels and verdicts compare across any two videos. Raw counts
and ratios only compare within the same duration and preset class.

`report.json` also carries, besides findings and positives: `reviewer` (which
model judged, ran and described — say so when one model did more than one
job), `requirements` (each
viewer-visible requirement of the request → `met | not-met | partial |
not-evaluable`, with finding ids — only what picture and sound can show),
`coverage` (frames described, frames the judge read, what the budget dropped),
and `escalate` (finding ids a bigger model or a person should look at).

**Before delivering: `python3 scripts/vqr.py check report.json` must print
`PASS`.** Then freeze it — record its sha256 — and do not edit it again. Later
corrections go in `addenda.json` beside it (`[{"what", "why"}]`), never into
the frozen file. Then `vqr.py notes report.json --out notes.json`.

## How to run it

### Who does what — observation is cheap, judgement is not

A review is three different jobs, and paying judgement prices for the first two
is the main way this skill gets expensive for no gain.

| job | tier | why |
|---|---|---|
| **Running the tools** — `vqr.py doctor / transcribe / measure / sheet / frames / strip / align / check / compare` | **Haiku** (runner) | One command, one file out. Nothing to decide. |
| **Describing frames and strips** — verbatim text, layout, what changed between tiles | **Haiku** (describer) | Pure observation. A bigger model does not see more; it costs more per frame, and there are ~150 of them. |
| **Judging** — choosing windows, turning candidates into findings, verifying on the frames, levels, severity, `report.json` | **Sonnet or larger** (judge) | This is where discretion lives. |
| **Arbitrating `escalate`** — every S4, any close call between two levels, any "is this intended?" the judge could not settle | **Opus / Fable, or the owner** | Few items, high stakes. |

Earlier versions of this skill reserved the verdict for a frontier model,
because a cheap model handed a pile of evidence produces "a confident,
well-formatted verdict arrived at by pattern-matching". That risk is real, and a
Sonnet judge is allowed here only because four things take the pattern-matching
away from it:

1. **The verdict is computed** by `vqr.py check` from the findings.
2. **Candidates come from arithmetic**, not from the judge's impression, and the
   candidate table says when each one counts.
3. **Low confidence caps severity at S2**, and S3/S4 require the judge to have
   read the frames itself (`verified_by_judge`).
4. **`escalate` is mandatory** for S4s and unresolved calls — the judge's job
   includes saying what it could not decide.

A judge that skips any of the four is the failure this rubric exists to
prevent, whatever its size.

**Get the evidence with the cheap tier, decide with the judge, escalate the
rest.**

### The steps

One working directory per video: `W=<out>/<label>`. `VQR=<skill>/scripts/vqr.py`
— the path alone, called as `"$VQR" <command>` (a variable holding
`python3 path` does not split into two words in zsh). Steps marked **R** are
the runner's, **D** the describer's, **J** the judge's. Ready-to-paste prompts
for R and D are in `references/prompts.md`.

If you cannot dispatch subagents, do R and D yourself, in this order: steps 0
and 2, then describe the P1 and P2 frames (step 4), and only then step 1 and
the rest. `measure` and `transcribe` print and store what the voice says; the
independence D4 depends on is between what was seen and what was said, and it
survives only if the seeing comes first. Say in `reviewer` that one model did
all three jobs.

**0 · Preflight (R).** `"$VQR" doctor`. If ffmpeg, numpy or Pillow is missing,
stop and say so. Write the request's facts to `$W/request.json`: language,
aspect, duration or range, safe zone if stated, whether subtitles are expected,
`subtitle_source`, `verify_subtitles`.

**1 · A1 — audio, always first (R).** Cheapest, and it tells the frame passes
where to look.

```bash
"$VQR" transcribe VIDEO --out $W --language <requested language>
"$VQR" measure VIDEO --out $W --transcript $W/transcript.json
```

`transcribe` re-runs ASR, language auto-detected, over every hole of 4s or more
that the first pass left — Whisper drops whole stretches after music or a clip
in another language, and an unpatched hole reads as "nobody spoke for 26
seconds". If the caller supplied a transcript and declined verification, skip
`transcribe` and pass theirs to `measure`. `measure` writes `mechanical.json`
(A1 + M1), strips for up to twelve flicker and eight reappearance candidates in
`$W/events/`, and prints a plain-language list of candidates — keep that
printout, it is the judge's worklist for step 6.

**2 · Sample (R).**

```bash
"$VQR" sheet  VIDEO $W/sheets --every 2
"$VQR" frames VIDEO $W/p1 --every 2 --prefix p1
"$VQR" frames VIDEO $W/p2 --fps 2 --from 0 --to 5 --prefix p2
```

**3 · Plan (J).** Read every contact sheet — they show the P1 instants,
twelve to eighteen per image — and the cut times in `measure`'s printout. Write
down:

- **Embedded clips**: footage with its own picture and sound playing inside the
  video (a meme video, a film clip). Take each one's span from the sheets and
  the hard cuts that enter and leave it. A still image or a screenshot is not
  a clip.
- **P3 windows**: both edges of every embedded clip; every cut with
  `|step_db| ≥ 20`; then other hard cuts, spread evenly, up to the budget.

Then one strip per window (R) — nine tiles from 1s before to 1s after:

```bash
"$VQR" around VIDEO $W/p3 --at <t1>,<t2>,<t3>
```

**4 · Describe (D), then build the timeline (R).** P1 and P2 frames in batches
of at most 15, one describer each, each writing `$W/describe/<batch>.jsonl` —
one JSON line per frame, keyed by the frame's file name. Then the P3 and event
strips, as prose. Fixed watch-list, for every frame:

- every on-screen text **verbatim**, with its region and role (`subtitle`,
  `heading`, `label`, `number`, `source-note`, `chrome`);
- what the picture shows, and whether it is an embedded clip;
- the D5 list: anything left over from another scene, anything covering the
  subject, overlaps, clipped words, text it could not read, shapes with no
  function, large empty areas;
- for a strip: what differs from tile to tile, and nothing else.

```bash
"$VQR" onscreen $W/describe --out $W/onscreen.json
```

`onscreen` builds the text timeline — each heading, label or number, from the
first to the last frame it was seen in — and takes every time **from the file
names**. A describer that slips a description onto the wrong frame cannot
then shift a timestamp; it happened in the first real run of this skill, by
4 seconds. Guard against the slip itself too: for each batch, the judge opens
one frame from its middle and compares it with that frame's line. If it does
not match, the batch is redone.

**The describer never sees the transcript**, the request, or any candidate
list. D4 is judged by aligning two *independently produced* streams, and a
describer that has been shown the narration sees content that matches it. Keep
`video-frame-review`'s `[unreadable]` discipline: a hedge is the trigger to
zoom (P4: `"$VQR" strip … --crop x:y:w:h --width 900`, or a full-width
`frames --at`), never an answer.

**5 · Align (R).** `"$VQR" align $W/transcript.json $W/onscreen.json --out $W/align.json`

**6 · Candidates → findings (J).** Walk `measure`'s candidate list and
`align.json` top to bottom with the candidate table. For each: decide from its
strip, and either write the finding or note in `coverage` why it is not one.
Then the describer's D5 observations.

When one kind of candidate repeats — thirty re-entries — read three strips
(first, middle, last); if all three show the same thing, it is one finding,
`f: recurring`, with the rest in `occurrences`.

**What the judge must read with its own eyes — the short list.** Everything
else may rest on the describer:
- every contact sheet;
- the entry and the exit strip of every embedded clip;
- the strip behind every finding at S3 or S4;
- one frame per describer batch (the slip check above);
- the frame or zoom behind any quote an S3 or S4 depends on.

**7 · Every embedded clip gets the same five questions (J).**

1. **Entry.** P3 strip at the entry cut + its `audio.cuts` row. Does it start
   mid-action or mid-word, from silence, or on top of an unfinished sentence
   (`said_before`)? An entry cut with `|step_db| ≥ 20` is a candidate whatever
   the words say — sound that snaps off or on is what "starts chopped" looks
   like in numbers. → `hard-clip-entry`
2. **Exit.** Same at the exit cut. And **what comes back**: is the screen after
   the clip one the viewer already saw before it (`reappearances` whose `again`
   starts at the exit)? → `screen-reappears`
3. **Its subtitles, if any.** Three sync probes (step 8), and — when the clip's
   speech is in another language — a translation check against the refilled
   transcript. → `sub-desync`, `sub-mismatch`
4. **Can its words be made out?** `low_confidence_speech` inside the span. →
   `asr-unintelligible`, low confidence. **Does its picture keep moving?** A
   `holds` entry inside the span → `frozen-picture`
5. **Is the voice talking about it?** The narration around the span, quoted. A
   clip nobody introduces or lands is `out-of-slot`.

**8 · Subtitles, if there are any (J plans, R extracts, D reads).** Pick five
subtitle events spread over the video, plus three inside each embedded clip —
all of them inside the clips when those are the only subtitles. For each, take
a word that starts its line and its ASR start `t`:

```bash
"$VQR" around VIDEO $W/p4 --at <t1>,<t2> --before 0.5 --after 1 --step 0.25 --crop 0:0.55:1:0.4 --width 540 --prefix sub
```

(Move the crop to wherever the sheets show the subtitles.) The first tile
showing the line brackets its onset to 0.25s — the resolution this check
declares. Text accuracy is the verbatim diff of the describer's subtitle
strings against the transcript, under the collusion rule; for a clip in
another language it is a check of sense, and it is `judged`.

**9 · Score, write, check, freeze (J).** Levels from the anchored text, each
justified by a finding or a positive it cites. Give every finding its `fix`
from `references/fix-recipes.md`. Write `$W/report.json`. Run
`"$VQR" check $W/report.json` until it prints `PASS`. Record its sha256. Run
`"$VQR" notes $W/report.json --out $W/notes.json`. Write the summary.

**10 · Calibrate — only if owner feedback exists, only now (J).** See
"Calibration".

### Verify before it becomes a finding

Cheap description is a lead, not evidence. In one run a describer reported
three men in numbered shirts on a frame that was actually an illustration
with "2026" printed on it — an invented frame, not a misread one. No finding
depended on it only because the orchestrator happened to look at that frame
directly; nothing in the process required it.

**An observation a finding rests on must be verified by the judge before it is
written up as a finding — at minimum:**
- Any finding at **S3 or S4**. Read the source frame(s) yourself; do not
  write the finding from the describer's text alone. `check` refuses an S3 or
  S4 without `verified_by_judge`.
- Anything **quoted verbatim** — a subtitle string, an on-screen number, a
  heading. Confirm it against the frame, not against the describer's
  transcription of it.

### Default cadence

Densify freely. **Never go sparser than this.**

| pass | cadence | serves |
|---|---|---|
| **A1** | audio only | D2, D3 audio edges, D4/D6 alignment |
| **M1** | every frame, thumbnail size | D3 flicker, reappearances, blank frames, holds |
| **P1** | fps=0.5, full video | D5 baseline, D4 sampling, subtitle OCR seed |
| **P2** | fps=2, 0–5s | D1 — dense, because the opening is what decides everything |
| **P3** | fps=4, ±1s around chosen cuts | D3 clip edges and transitions |
| **P4** | targeted zooms on text-bearing regions | D4/D5/D6 |

### Frame budget

For a 3-minute video. Scale P1 and the sheets with duration; the caps do not
scale.

| what | images | read by |
|---|---|---|
| contact sheets | ~6 | judge |
| P1 frames | ~90 | describer |
| P2 frames | 10 | describer |
| P3 strips (9 tiles each) | ≤ 20 | describer |
| M1 event strips | ≤ 20 (`measure` makes 12 flicker + 8 reappearance) | describer |
| P4 zooms and subtitle probes | ≤ 25 | describer |
| the judge's own reads (the short list in step 6) | ≤ 40 | judge |

When a cap cuts something — forty cuts and twenty strips — choose by the plan
in step 3 and **list what was dropped in `coverage.dropped`**. A capped pass
that reports as if it were complete is the sparse-sampling lie in a new place.

## Family mode — N videos from the same request

Use it when several videos answer one request: the same brief given to
different generators, profiles or versions. **Read
`references/family-mode.md` before starting one.** In short:

1. **Label blind** — `V1..Vn`; nothing about who or what made each video
   enters any report.
2. **One plan for all** — same passes, cadences, caps, prompts.
3. **One fresh judge per video** — steps 0–9 in separate contexts, every
   `report.json` frozen before any comparing.
4. **`vqr.py compare`** — the table, the computed ordering (ties stay ties),
   the classes not shared, and which videos share one audio track.
5. **Side-by-side strips** at the same moments, one row per video.
6. **Differences** — each a claim with evidence from both videos, tagged
   `measured|judged` and a confidence; absence claimed only where coverage
   was equal.

Output: one `report.json` per video + `family.json` + a summary (table,
ordering, five to ten differences, what was not comparable).

## Calibration — against the owner's feedback, after the freeze

When the owner has said what they saw in a video, that is the best ground truth
this review will ever get — and the quickest way to ruin the review is to read
it first.

1. Freeze `report.json` (sha256). Only then open the feedback.
2. Write `calibration.json` beside it. Split the feedback into single
   statements, **quoted verbatim**, each with one outcome:
   - `hit` — finding ids that say the same thing;
   - `miss` — with a reason: `not-sampled`, `seen-not-flagged`,
     `below-threshold`, `no-check-for-it`;
   - `not-perceivable-offline` — it needs ears (the music is monotonous, a
     voice sounds off);
   - `preference` — a creative wish, not a defect ("I'd have picked a livelier
     style").
3. `recall = hits / (hits + misses)`. Also list your S3+ findings the owner did
   not mention — not errors, but the place to look for over-reporting.
4. **Never edit the frozen report.** What the feedback makes you go back and
   find goes in `calibration.json` → `late_findings`, marked as found after
   reading the feedback. It does not change the blind verdict.
5. A miss teaches the *next* video a class to look harder for — "re-entries at
   scene starts", never "V3 probably flickers at 01:05". Pass class-level
   lessons forward; pass nothing about a specific video that has not been
   frozen.
6. The owner's score is a number of its own. Compare *orderings* inside a
   family (does your ordering agree with theirs?); never convert a verdict to
   a score or back.

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

- **Prosody, pronunciation, music-vs-voice mix, whether a clip is
  intelligible** — you do not hear audio, and you are forbidden to play it.
  Proxying this from a transcript is guessing. ASR confidence is a lead for a
  person to follow, which is why `asr-unintelligible` can never be more than
  `confidence: low`.
- **External factual truth** — you have no sources, and that includes
  geography read off a drawn map. D4 covers only *internal*
  contradiction between channels. "The claim is false" is not yours to make;
  "the screen and the voice disagree" is.
- **Actual retention** — you have no audience. The hook level is a craft
  judgement and must never be phrased as a retention measurement.
- **Ken Burns naturalness outside densified windows** — motion inferred from two
  sparse stills is not observed motion.
- **Identity consistency when there is no identifiable subject** — a video of
  objects, places or data has no face, kit or crest to contradict. Half of D5's
  detection power is identity, and on this material that half has an empty
  candidate set: it cannot fail, so its passing means nothing. Report
  `NOT SCORED — no identifiable subject` for that component and score D5's
  remaining components (legible embedded text, sharpness, palette consistency)
  as normal. **Do not fold the missing component into a `Clean`** — a reader
  comparing two videos would read equivalence where there is none.

**Accepted blind spot.** M1 looks at every frame, so a flash, a blink or a
replayed entrance between two P1 samples is now caught. What it cannot see is
anything that *arrives and stays wrong*: a garbled label, an overlap, a wrong
number that appears and resolves inside a P1 2-second gap, away from any cut,
will still be missed — M1 knows pixels changed, not what they say. The
alternative is describing every frame, which the cadence plan exists to avoid.
The mitigation is that real defects cluster at cuts, openings and text — which
is exactly where the dense passes sit. Say this in the report rather than
implying full coverage.

**What M1 gets wrong.** It works on thumbnails with fixed thresholds:
- A gentle flicker under ~4% of the frame, or one that fades both ways, is
  below it.
- Live footage inside a clip produces `re-entry` and `blink` candidates from
  ordinary movement — the strip settles it in a second.
- Dark, low-contrast videos produce `reappearances` between shots that are
  merely similar; and a drama that cuts back and forth produces many true ones
  that are not defects.
- Dissolves are not hard cuts, so they get no `audio.cuts` row and no P3 window
  unless the judge adds one from the contact sheets.

**ASR holes.** Whisper-family engines skip audio after music or a
foreign-language stretch. `transcribe` patches holes of 4s and up and reports
them (`refilled_windows`); shorter ones remain. A `speech_gap` with
`as_loud_as_speech: true` is the mark of one — never a silence finding.

## What this rubric deliberately does not cover

Three things the previous rubric scored are **out of scope here**, because they
need exactly the database and log access this reviewer is denied:

- Whether the output matches the configuration that was requested of the
  generator, beyond the three gates in D1. (Requirements a viewer can check —
  "no subtitles", "logos when named" — are not configuration; they go in
  `requirements`.)
- Pipeline integrity.
- Cost and efficiency — in family mode too: which video was cheaper is not
  something this review knows.

They are not worthless — they belong to an automated audit that runs *beside*
this review, not inside it.

One piece of the previous rubric is not merely dropped but **contradicted**: the
guidance to watch at normal speed and only dig where something jars. A model
reviewer cannot watch at normal speed, and sparse sampling is not a cheaper
version of looking — at 1 fps it is not looking at all. The cadence plan
replaces it.
