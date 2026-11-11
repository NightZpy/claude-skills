# Fix recipes — one per defect class

How to write `fix` for each class: the edit, the target value, and the check
that shows it worked. Fill the `<…>` slots from the finding's own evidence.
Numbers come from the pass that measured them and are no finer than it: a
subtitle offset bracketed by 0.25s probes is "0.25–0.5s", not "0.3s".

`verify` always starts with the check to re-run:

- `measure:` — a field of `mechanical.json` after `vqr.py measure` on the new
  file ("no `visual.flashes` event in [65.2, 66.2]").
- `align:` — a row of `vqr.py align` ("«LO QUE HAY DEBAJO» is `in-slot`").
- `probe:` — a frame or strip at stated times and what must be read there
  ("strip at 9.0, 9.25, 9.5: the line «Me encanta» first appears at 9.25").
- `listen:` — only a person's ears can confirm it. Say what they listen for.

## D3 — edit, motion, pacing

| class | action | what → target | verify |
|---|---|---|---|
| `flicker` (`re-entry`) | `hide` | `<element>` in `[scene start, entrance start]` → absent until its entrance begins; it enters once | `measure:` no `flashes` event in `<interval>` |
| `flicker` (`flash`, `blink`) | `remove` | the `<n>` stray frames at `<t>` → the frames before and after are contiguous | `measure:` no `flashes` event in `<interval>` |
| `blank-frame` | `remove` | the `<n>` blank frames at `<t>` → none | `measure:` no `blank_frames` with `position: middle` and `hard_edges` |
| `screen-reappears` | `hide` | `<screen>` during whichever showing is out of slot (`first` or `again` — the one `align` does not put `in-slot`) → shown once, where the voice is on it | `measure:` no `reappearances` pair for it · `align:` its text `in-slot` |
| `hard-clip-entry` | `retime` + `fade` | the clip's start → after the sentence in `said_before` ends, on a pause; audio fades in over ≥ 3 frames | `measure:` that cut's `|step_db| < 20` and no `inside_word` |
| `hard-clip-exit` | `retime` + `fade` | the clip's end → after its last word ends; audio fades out over ≥ 3 frames | same |
| `cut-in-word` | `retime` | the cut at `<t>` → inside the pause between `<word A>` (ends `<tA>`) and `<word B>` (starts `<tB>`) | `measure:` that cut's `|step_db| < 20` |
| `reveal-done-early` | `retime` | the reveal of `<element>` → starts when the segment appears, not before | `probe:` first and last frame of the segment differ |
| `transition-mismatch` | `replace` | the transition at `<t>` → a hard cut (continuous flow) or a dissolve (time/topic shift), whichever the content event is | `probe:` strip across `<t>` |
| `pacing-slow` | `add` or `trim` | the hold `<interval>` → a visual change at least every 8s while the voice continues, or the hold trimmed to the length of what is said over it | `measure:` no `holds` entry ≥ 8s overlapping speech in `<interval>` |
| `pacing-rushed` | `trim` → extend | `<text or graphic>` → on screen ≥ `chars / 17` seconds | `probe:` first and last frame showing it |

The 8-second and 3-frame targets are *chosen by us*. Say so when you cite them.

When two fixes apply to one finding (retime **and** fade), write the main one
as `action` and put the other in `target`.

## D2 — audio

| class | action | what → target | verify |
|---|---|---|---|
| `loudness` | `level` | the whole mix → `<−16 − measured>` LU of gain, landing in [−18, −14] LUFS | `measure:` `integrated_lufs` in range |
| `true-peak` | `level` | the whole mix → true peak ≤ −1 dBTP (limit, not just gain) | `measure:` `true_peak_dbtp ≤ −1` |
| `audio-hole` | `add` | the bed across `<interval>` → continuous through it | `measure:` no `dead_air` in `<interval>` |
| `dead-air` | `trim` or `add` | the silent gap `<interval>` → ≤ 1.5s, or carried by a bed | `measure:` no `dead_air` / quiet `speech_gaps` ≥ 1.5s there |
| `orphan-audio` | `remove` | the sound at `<interval>` → muted | `measure:` no `orphan_bursts` there · `listen:` no click or word fragment |
| `asr-unintelligible` | `remove`, **conditional** | the clip's dialogue subtitles (or the clip) in `<interval>` → gone. `condition`: "a person listens to `<interval>` and cannot make the words out either" | `listen:` the words in `<interval>` |

## D4 — narration ↔ picture

| class | action | what → target | verify |
|---|---|---|---|
| `out-of-slot` | `retime` or `hide` | `<text or image>` → on screen only around its own mention at `<A1 time>` (enter ≤ 2s before it), not during `<interval>` where the voice says «`<quote>`» | `align:` it is `in-slot` |
| `stray-label` | `remove` | the label «`<text>`» in `<region>` → gone | `probe:` frame at `<t>` does not show it |
| `duplicate-data` | `remove` | the second «`<value + heading>`» → one occurrence | `probe:` frame at `<t>` |
| `filler` | `replace` | the generic image in `<interval>` → a picture of the specific claim «`<quote>`» | `probe:` frames in `<interval>` |
| `number-mismatch` | — | **not formulable**: screen says «`<n1>`», voice says «`<n2>`»; which is right needs the source. Once known: `replace` the wrong one | — |
| `contradiction` | — | **not formulable** for the same reason, unless the request itself states the fact | — |

## D5 — visual integrity

| class | action | what → target | verify |
|---|---|---|---|
| `layer-out-of-slot` | `hide` | the leftover `<element>` in `<region>` during `<interval>` → not visible | `probe:` frame at `<t>` |
| `occluded-subject` | `move` or `resize` | `<panel>` → clear of `<subject>`; the subject fully visible | `probe:` frame at `<t>` |
| `overlap` | `move` | `<A>` and `<B>` → no intersection, a visible gap between them | `probe:` frame at `<t>` — at the worst moment of any motion, not only at rest |
| `text-clipped` | `move` or `resize` | «`<text>`» → whole inside the frame / its box, with margin | `probe:` frame at `<t>` |
| `text-illegible` | `resize` or `restyle` | «`<text>`» → readable at delivery size without zoom: contrast ≥ 4.5:1, on screen ≥ `chars / 17` s, and large enough that a describer reads it from the full frame | `probe:` full frame at `<t>`, no zoom |
| `artifact-shape` | `remove` | the `<disc / plate / bar>` in `<region>` during `<interval>` → gone | `probe:` frame at `<t>` |
| `empty-space` | `move` | the content in `<interval>` → spread over the frame; no dead area larger than a third of it | `probe:` frame at `<t>` |
| `unrequested-chrome` | `remove` | the `<progress bar / counter / banner>` → gone for the whole video | `probe:` sheets |
| `style-break` | `restyle` | the scene `<interval>` → the palette and rendering style of its neighbours | `probe:` side-by-side strip with the scenes before and after |
| `gibberish-text` | `replace` | «`<garbled>`» → the words the voice says at that moment, «`<quote>`», when it says them. Otherwise **not formulable**: the intended text is not in the video | `probe:` zoom at `<t>` |
| `identity` | — | **not formulable**: who or what it should be needs a reference the video does not contain | — |

## D6 — subtitles and on-screen text

| class | action | what → target | verify |
|---|---|---|---|
| `sub-desync` | `retime` | the subtitles in `<interval>` → `<earlier / later>` by `<bracket>`; onset within 0.25s of the word | `probe:` the same five-tile strip |
| `sub-mismatch` | `replace` | the line «`<burned>`» → «`<ASR quote>`» — only when the ASR is independent and confident there; otherwise `condition`: "a person confirms the words" | `probe:` zoom at `<t>` |
| `sub-out-safe` | `move` | the subtitle line → inside the safe zone (`<the request's, or the default>`) | `probe:` frame at `<t>` |
| `sub-contrast` | `restyle` | the subtitle line → backing or outline giving ≥ 4.5:1 on its worst frame | `probe:` frame at `<worst t>` |
| `sub-speed` | `retime` | the line «`<text>`» → on screen ≥ `chars / 17` s, or split in two | `probe:` first and last frame showing it |
| `sub-overlap` | `move` | the subtitle line → clear of `<the other text>` | `probe:` frame at `<t>` |

## D1 — hook and gates

| class | action | what → target | verify |
|---|---|---|---|
| `weak-hook` | `retime` | the shot or claim now at `<t>` → inside the first 2s, when the video contains the payoff material. If it does not, **not formulable**: a new opening has to be written | `probe:` P2 frames |
| `undelivered-promise` | — | **not formulable**: the content promised at `<t>` is not in the video | — |
| `gate-duration` | `trim` | the video → inside `<range>`; name the stretches this report already flags as slow | `measure:` `duration_s` |
| `gate-aspect`, `gate-language` | — | **not formulable** as a note: the whole piece is to be redone at `<requested>` | — |

## When to answer "not formulable"

Say `formulable: false` with a `why` when writing the fix would need something
that is not in the picture or the sound:

- **which of two disagreeing channels is right** (number, name, claim);
- **what a garbled or missing thing was meant to be**;
- **material the video does not contain** (a payoff, a correct likeness);
- **a whole-piece redo** (aspect, language).

`why` names exactly what is missing — "the source figure for chip exports" —
so that whoever has it can finish the note. An invented fix is worse than an
honest gap: it sends someone to change the right thing to the wrong value.
