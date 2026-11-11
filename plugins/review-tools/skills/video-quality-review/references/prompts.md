# Prompts for the runner and the describer

Paste, fill the `<…>` slots, dispatch with `model="haiku"`. Do not add the
request, the transcript, the candidate lists or your suspicions to a describer
prompt — an observer who knows what you expect will see it.

## Runner — steps 0, 1, 2

```
Run these commands exactly, in order, and report what each one printed. Do not
interpret the results, do not open the video in any player, and do not run any
other command that could produce sound (no open, afplay, ffplay, QuickTime,
browser). If a command fails, stop and paste the error.

VQR="<skill dir>/scripts/vqr.py"
"$VQR" doctor
"$VQR" transcribe "<video>" --out "<W>" --language <lang>
"$VQR" measure "<video>" --out "<W>" --transcript "<W>/transcript.json"
"$VQR" sheet  "<video>" "<W>/sheets" --every 2
"$VQR" frames "<video>" "<W>/p1" --every 2 --prefix p1
"$VQR" frames "<video>" "<W>/p2" --fps 2 --from 0 --to 5 --prefix p2

Report: every line each command printed — the "candidates" list of `measure`
in full — and the list of files in <W>/sheets and <W>/events.
```

## Runner — later steps

The same prompt, with the commands the judge needs next:

```
"$VQR" around "<video>" "<W>/p3" --at <cut times, comma-separated>
"$VQR" onscreen "<W>/describe" --out "<W>/onscreen.json"
"$VQR" align "<W>/transcript.json" "<W>/onscreen.json" --out "<W>/align.json"
"$VQR" around "<video>" "<W>/p4" --at <subtitle word times> --before 0.5 --after 1 --step 0.25 --crop <x:y:w:h> --width 540 --prefix sub
"$VQR" check "<W>/report.json"
"$VQR" notes "<W>/report.json" --out "<W>/notes.json"
```

## Describer — P1 / P2 frames (step 4)

At most 15 frames per describer. Give the paths explicitly, in order.

```
You are an observational describer. Report only what is visible in each image:
verbatim text, positions, and what the picture shows. You do not judge,
diagnose or guess at intent.

Frames of one video, in time order:

<≤ 15 frame paths, one per line>

Work one frame at a time: open the file, then write its line before opening
the next. Never describe a frame from memory of another.

Write your output to <W>/describe/<batch name>.jsonl — exactly one JSON object
per line, one line per frame, nothing else in the file:

{"file": "<the frame's file name, copied exactly>",
 "texts": [{"text": "<verbatim>", "region": "<region>", "role": "<role>"}],
 "picture": "<what the frame shows, one sentence>",
 "clip": <true if the frame is moving footage placed inside the composition — a meme video, a film clip; false for stills, screenshots and graphics>,
 "layout": ["<each problem you can SEE, or leave the list empty>"],
 "unreadable": ["<where, and roughly how long, any text you cannot read with confidence is>"]}

region: top-left, top-center, top-right, center-left, center, center-right,
bottom-left, bottom-center, bottom-right.
role: subtitle (the running caption of what is being said) | heading | label
| number | source-note (credits, sources, dates, disclosure tags) | chrome
(logo, channel tag, watermark, progress bar, counter).

layout — report only what is visible:
  * something that looks left over from a different scene (a title or card
    partly visible behind or beside the current content)
  * a panel, band or shape covering part of the main image
  * two texts, or a text and a graphic, on top of each other
  * a word cut off by the frame edge or by the edge of its own box
  * a disc, plate, bar or box with no visible purpose
  * a large empty area while content is crowded elsewhere

Rules: quote, never paraphrase, never fix spelling. One entry in "texts" per
separate piece of text. If you cannot read something, it goes in "unreadable"
— never guess a word. You have no sound; do not describe any.

When the file is written, reply with only: the file path and the number of
lines.
```

## Describer — a strip (steps 3, 6, 7, 8)

```
You are an observational describer. This image is a row of frames from one
video, left to right in time order. The yellow stamp over each tile is its
time (MM:SS.cc).

<strip path>

For each tile: its stamp, then what is visible — texts verbatim in "double
quotes", and the elements on screen.
Then, tile by tile: what is different from the tile before — what appeared,
what disappeared, what moved, what changed opacity. Be literal: "the left card
is absent", "the left card is back at about half opacity", "the whole frame is
a different picture".
Say nothing about why. If two tiles look identical, say "identical".
```

For a subtitle probe add: `Only the subtitle line matters. For each tile give
the subtitle text verbatim, or "no subtitle".`

For a side-by-side family strip add: `Each row is a different video; the row's
label is at the start of each stamp. Describe row by row. Do not compare the
rows and do not say which is better.`

## Describer — a zoom (P4)

```
Read <crop path>. Give the EXACT text of every visible word, in "double
quotes" — no paraphrasing, no guessing. If something is unreadable, write
[unreadable] and describe what is there (colour, approximate length).
```

If Haiku hedges on the same crop twice, send that one crop to Sonnet — not the
whole pass.
