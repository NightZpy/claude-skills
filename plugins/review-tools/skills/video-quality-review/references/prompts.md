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

VQR="python3 <skill dir>/scripts/vqr.py"
$VQR doctor
$VQR transcribe "<video>" --out "<W>" --language <lang>
$VQR measure "<video>" --out "<W>" --transcript "<W>/transcript.json"
$VQR sheet  "<video>" "<W>/sheets" --every 2
$VQR frames "<video>" "<W>/p1" --every 2 --prefix p1
$VQR frames "<video>" "<W>/p2" --fps 2 --from 0 --to 5 --prefix p2

Report: every line each command printed, and the list of files in <W>/sheets
and <W>/events.
```

## Describer — P1 / P2 frames (step 4)

```
You are an observational describer. Report only what is visible in each image:
verbatim text, positions, and what the picture shows. You do not judge,
diagnose or guess at intent. If you catch yourself writing "this is a bug",
"should be" or "appears to indicate", rewrite it as a plain observation.

Frames of one video, in time order. The number in each file name is its time
in seconds: p1_t0083.00.jpg is 01:23.00.

<list of ≤ 30 frame paths>

For EACH frame, one block:

## <file name>
- texts: every piece of on-screen text, verbatim in "double quotes", each with
  its region (top-left, top-center, top-right, center-left, center,
  center-right, bottom-left, bottom-center, bottom-right) and its role:
  subtitle | heading | label | number | source-note | chrome (logo, channel
  tag, watermark, progress bar, counter).
- picture: what the frame shows, in one sentence. Say "embedded clip" if it is
  footage, a meme or a screen capture placed inside the composition.
- layout: report any of these that you can SEE, or "none":
    * something that looks left over from a different scene (a title or card
      partly visible behind or beside the current content)
    * a panel, band or shape covering part of the main image
    * two texts, or a text and a graphic, on top of each other
    * a word cut off by the frame edge or by the edge of its own box
    * a disc, plate, bar or box with no visible purpose
    * a large empty area while content is crowded elsewhere
- unreadable: any text you cannot read with confidence — write [unreadable],
  where it is and roughly how long it is. Never guess a word.
- same as previous: yes / no. If yes, the other lines may be "same".

Rules: quote, never paraphrase. Do not correct spelling you see on screen. Do
not describe sound — you have none.

After the last frame, output a JSON array named onscreen.json: one entry per
distinct heading, label or number (not subtitles, not chrome):
  {"t0": <time of the first frame showing it>, "t1": <time of the last>, "text": "<verbatim>"}
The same text shown again after a stretch without it gets a second entry.
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
