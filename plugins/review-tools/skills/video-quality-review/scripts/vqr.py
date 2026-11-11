#!/usr/bin/env python3
"""vqr — the mechanical half of video-quality-review.

Everything here is measured from the file. ffmpeg decodes to a pipe, to a file
or to `-f null`; there is no code path to an audio device (no ffplay, afplay,
open). Needs ffmpeg/ffprobe; numpy for `measure`; Pillow for `sheet`/`strip`.

  vqr.py doctor
  vqr.py transcribe VIDEO --out DIR [--language es]
  vqr.py measure VIDEO --out DIR [--transcript DIR/transcript.json]
  vqr.py frames VIDEO DIR (--every S | --fps N --from A --to B | --at T,T,..)
  vqr.py sheet VIDEO DIR [--every 2]
  vqr.py strip OUT.jpg LABEL=VIDEO@T,T,.. [LABEL=VIDEO@T,T,..]
  vqr.py align TRANSCRIPT.json ONSCREEN.json
  vqr.py check REPORT.json | FAMILY.json
  vqr.py compare DIR DIR [DIR ..] --out FAMILY.json
  vqr.py self-test
"""
import argparse, hashlib, io, json, math, os, re, shutil, subprocess, sys, tempfile, unicodedata

CELLS = ["top-left", "top-center", "top-right", "center-left", "center", "center-right",
         "bottom-left", "bottom-center", "bottom-right"]
LEVELS = ["Clean", "Rough", "Distracting", "Broken"]
VERDICTS = ["SHIP", "SHIP WITH FIXES", "DO NOT SHIP"]
S4_REASONS = ["fabricated-claim", "gibberish-as-information", "wrong-identity",
              "unintelligible-narration", "d1-gate"]


def sh(cmd):
    return subprocess.run(cmd, capture_output=True)


def die(msg):
    sys.exit(f"vqr: {msg}")


def resolve(video):
    # macOS hands out NFD paths and shells type NFC ones; try both before giving up.
    for cand in (video, unicodedata.normalize("NFC", video), unicodedata.normalize("NFD", video)):
        if os.path.isfile(cand):
            return cand
    die(f"no such file: {video}")


def probe(video):
    r = sh(["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", video])
    d = json.loads(r.stdout or b"{}")
    v = next((s for s in d.get("streams", []) if s["codec_type"] == "video"), None)
    if not v:
        die(f"no video stream in {video}")
    rate = v["avg_frame_rate"] if v.get("avg_frame_rate", "0/0") != "0/0" else v["r_frame_rate"]
    num, den = (float(x) for x in rate.split("/"))
    g = math.gcd(v["width"], v["height"])
    return {"duration_s": round(float(d["format"]["duration"]), 3), "width": v["width"],
            "height": v["height"], "aspect": f"{v['width'] // g}:{v['height'] // g}",
            "fps": round(num / den, 3), "fps_str": rate,
            "has_audio": any(s["codec_type"] == "audio" for s in d["streams"])}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def clock(t):
    return f"{int(t // 60):02d}:{t % 60:05.2f}"


def runs(mask, min_len=1):
    """[(start, end_exclusive)] for each run of True in a boolean sequence."""
    out, start = [], None
    for i, m in enumerate(list(mask) + [False]):
        if m and start is None:
            start = i
        elif not m and start is not None:
            if i - start >= min_len:
                out.append((start, i))
            start = None
    return out


def load_words(path):
    """[(word, start, end, prob)] from whisper/mlx-whisper JSON or a plain [{word,start,end}] list."""
    d = json.load(open(path))
    items = d if isinstance(d, list) else [w for s in d.get("segments", []) for w in s.get("words", [])]
    words = [(w["word"].strip(), float(w["start"]), float(w["end"]),
              float(w.get("probability", w.get("p", 1.0)))) for w in items if w.get("word", "").strip()]
    if not words:
        die(f"{path} has no word timings — transcribe again with word timestamps")
    return words


# ---------------------------------------------------------------- measure

def audio_measures(video, cuts, words):
    import numpy as np
    r = sh(["ffmpeg", "-hide_banner", "-nostats", "-i", video, "-vn",
            "-af", "loudnorm=print_format=json", "-f", "null", "-"])
    ln = json.loads(re.findall(r"\{[^{}]*\}", r.stderr.decode(errors="replace"))[-1])
    pcm = np.frombuffer(sh(["ffmpeg", "-v", "error", "-i", video, "-vn", "-ac", "1", "-ar", "8000",
                            "-f", "s16le", "-"]).stdout, np.int16).astype(np.float64)
    n = len(pcm) // 80                                   # 10 ms windows
    rms = np.sqrt((pcm[:n * 80].reshape(n, 80) ** 2).mean(axis=1))
    db = 20 * np.log10(np.maximum(rms, 1.0) / 32768.0)   # floor ≈ -90 dBFS

    def level(a, b):
        seg = db[max(0, int(a * 100)):max(0, int(b * 100))]
        return round(float(seg.mean()), 1) if len(seg) else None

    out = {"integrated_lufs": float(ln["input_i"]), "true_peak_dbtp": float(ln["input_tp"]),
           "lra_lu": float(ln["input_lra"]), "resolution_s": 0.01}
    dur = n / 100
    # Digital silence. Under a continuous bed even 0.15 s of it is a hole; in a track that goes
    # silent between sentences it is just a pause, so there only 1.5 s counts.
    out["continuous_bed"] = bool((db < -60).mean() < 0.05)
    out["dead_air"] = [{"t": [s / 100, e / 100], "position": "start" if s == 0 else "end" if e >= n - 5 else "middle",
                        "around_db": [level(s / 100 - 0.3, s / 100), level(e / 100, e / 100 + 0.3)]}
                       for s, e in runs(db < -60, 15 if out["continuous_bed"] else 150)]

    # Short sounds standing alone in a quiet stretch: clicks, pops, the tail of a cut word.
    pad = np.pad(db, 100, mode="edge")
    floor = np.median(np.lib.stride_tricks.sliding_window_view(pad, 201), axis=1)
    bursts = []
    for s, e in runs(db >= floor + 12, 3) if words else []:   # without a transcript every syllable looks orphaned
        if e - s > 40:
            continue
        before, after = db[max(0, s - 30):s], db[e:e + 30]
        if len(before) and len(after) and before.mean() <= floor[s] + 6 and after.mean() <= floor[s] + 6:
            said = [w for w in words if w[1] < e / 100 + 0.25 and w[2] > s / 100 - 0.25]
            if not said:
                bursts.append({"t": [s / 100, e / 100], "over_floor_db": round(float(db[s:e].max() - floor[s]), 1)})
    out["orphan_bursts"] = bursts[:30] if words else None

    out["cuts"] = []
    for t in cuts:
        pre, post = level(t - 0.30, t - 0.05), level(t, t + 0.10)
        row = {"t": t, "pre_db": pre, "post_db": post,
               "step_db": None if pre is None or post is None else round(post - pre, 1)}
        inside = [w for w in words if w[1] + 0.05 < t < w[2] - 0.05]
        if inside:
            row["inside_word"] = {"word": inside[0][0], "t": [inside[0][1], inside[0][2]]}
        if words:
            row["said_before"] = " ".join(w[0] for w in words if t - 1.5 <= w[2] <= t + 0.05)
            row["said_after"] = " ".join(w[0] for w in words if t - 0.05 <= w[1] <= t + 1.5)
        out["cuts"].append(row)

    if words:
        gaps = [(0.0, words[0][1])] + [(a[2], b[1]) for a, b in zip(words, words[1:])] + [(words[-1][2], dur)]
        talk_db = float(np.median([x for x in (level(w[1], w[2]) for w in words) if x is not None]))
        # A gap in the transcript is not silence: music, another language or an ASR dropout all look the same here.
        out["speech_gaps"] = [{"t": [round(a, 2), round(b, 2)], "s": round(b - a, 2), "level_db": level(a, b),
                               "as_loud_as_speech": (level(a, b) or -90) >= talk_db - 6}
                              for a, b in gaps if b - a >= 1.5]
        out["speech_level_db"] = round(talk_db, 1)
        span = (words[-1][2] - words[0][1]) / 60
        out["words_per_minute"] = round(len(words) / span, 1) if span > 0 else None
        lows = runs([w[3] < 0.5 for w in words], 2)
        out["low_confidence_speech"] = [{"t": [words[s][1], words[e - 1][2]],
                                         "text": " ".join(w[0] for w in words[s:e]),
                                         "mean_p": round(sum(w[3] for w in words[s:e]) / (e - s), 2)}
                                        for s, e in lows]
    m = n // 10
    out["envelope_100ms_db"] = [int(round(x)) for x in db[:m * 10].reshape(m, 10).mean(axis=1)]
    return out


def visual_measures(video, p):
    import numpy as np
    W, H = (96, 54) if p["width"] >= p["height"] else (54, 96)
    # ponytail: every frame held in memory (~5 KB each). Fine to ~1 h at 30 fps; stream in chunks beyond that.
    raw = sh(["ffmpeg", "-v", "error", "-i", video, "-an",
              "-vf", f"fps={p['fps_str']},scale={W}:{H}:flags=area,format=gray", "-f", "rawvideo", "-"]).stdout
    F = np.frombuffer(raw, np.uint8).reshape(-1, H, W)
    n, fps = len(F), p["fps"]

    def T(i):
        return round(i / fps, 3)

    def blk(a):                                          # (.., H, W) -> (.., 6, 6) block means
        return a.reshape(*a.shape[:-2], 6, H // 6, 6, W // 6).mean(axis=(-3, -1))

    def dist(a, ref):
        return blk(np.abs(a.astype(np.int16) - ref.astype(np.int16)))

    def region(hot):                                     # 6x6 bool -> 3x3 names
        cells = [CELLS[r * 3 + c] for r in range(3) for c in range(3) if hot[r * 2:r * 2 + 2, c * 2:c * 2 + 2].any()]
        return ["full-frame"] if len(cells) >= 7 else cells

    bd = np.zeros((n, 6, 6), np.float32)                 # block distance to the previous frame
    for s in range(1, n, 4000):
        e = min(n, s + 4000)
        bd[s:e] = dist(F[s:e], F[s - 1:e - 1])
    g, mx, frac = bd.mean(axis=(1, 2)), bd.max(axis=(1, 2)), (bd >= 8).mean(axis=(1, 2))

    # Hard cuts: most of the frame changes at once, and the frames around it do not.
    cuts = []
    for i in np.where((g >= 14) & (frac >= 0.6))[0]:
        near = np.concatenate([g[max(1, i - 5):i], g[i + 1:i + 6]])
        if not len(near) or g[i] >= 3 * max(float(np.median(near)), 1.0):
            cuts.append(int(i))

    # Excursions: the picture jumps away abruptly and is back at the exact prior state within 1.5 s.
    # A cut, a reveal or a subtitle change never comes back, so none of those can land here.
    # flash = gone within 0.2 s · blink = longer, snaps back · re-entry = snaps away, eases back
    # (an element already on screen that vanishes and replays its entrance).
    K, flashes, i = max(2, int(round(fps * 1.5))), [], 1
    while i < n - 1:
        if mx[i] < 10:
            i += 1
            continue
        d = dist(F[i:i + K], F[i - 1])
        dmax = d.max(axis=(1, 2))
        k = next((k for k in range(1, len(dmax)) if dmax[k] <= max(2.5, 0.05 * dmax[:k].max())), None)
        if k:
            peak = float(dmax[:k].max())
            kind = "re-entry" if mx[i + k] < 0.5 * peak else "flash" if k / fps <= 0.2 else "blink"
            if kind == "blink" and k / fps > 0.5:        # a caption that stays half a second was meant to be read
                i += 1
                continue
            flashes.append({"t": [T(i), T(i + k)], "frames": k, "kind": kind,
                            "region": region(d[:k].max(axis=0) >= 0.5 * peak), "magnitude": round(peak, 1)})
            i += k + 1
        else:
            i += 1
    for f in flashes:
        f["repeats_within_2s"] = sum(1 for o in flashes if o is not f and abs(o["t"][0] - f["t"][0]) <= 2.0
                                     and set(o["region"]) & set(f["region"]))

    std = F.reshape(n, -1).std(axis=1)
    blanks = [{"t": [T(s), T(e)], "luma": int(F[s].mean()),
               "position": "start" if s == 0 else "end" if e >= n else "middle",
               # a fade through black eases in and out; a glitch snaps
               "hard_edges": bool(mx[s] >= 10 or (e < n and mx[e] >= 10))} for s, e in runs(std < 4)]
    still = mx <= 1.5
    still[0] = True
    holds = sorted(({"t": [T(s), T(e)], "s": round((e - s) / fps, 2)} for s, e in runs(still, int(2 * fps))),
                   key=lambda h: -h["s"])

    # Reappearances: a screen seen before, something else shown in between, the same screen again.
    # ponytail: O(samples²) at 2 samples/s — seconds for a 10-minute video, minutes for an hour.
    step = max(1, int(round(fps / 2)))
    idx = [j for j in range(0, n, step) if std[j] >= 4]
    S, pairs = F[idx], []
    for j in range(4, len(idx)):
        D = dist(S[:j], S[j])
        other = np.where((D >= 8).mean(axis=(1, 2)) >= 0.33)[0]
        if not len(other):
            continue
        # Near-identical, not identical: a screen that drifts or breathes is still the same screen.
        same = np.where((D.max(axis=(1, 2)) <= 12.0) & (D.mean(axis=(1, 2)) <= 2.5))[0]
        same = same[same < other.max()]
        if len(same):
            lo = hi = int(same.min())                    # the first showing: the earliest run of matches
            while hi + 1 in same:
                hi += 1
            pairs.append((j, lo, hi))
    recur = []
    for j, lo, hi in pairs:
        if recur and recur[-1]["_j"] >= j - 2:           # one odd sample does not split a screen in two
            recur[-1]["_j"], recur[-1]["again"][1] = j, T(idx[j])
        else:                                            # sample times, 0.5 s apart
            recur.append({"first": [T(idx[lo]), T(idx[hi])], "again": [T(idx[j]), T(idx[j])], "_j": j})
    for r in recur:
        r["away_s"] = round(r["again"][0] - r["first"][1], 2)
        del r["_j"]

    minutes = n / fps / 60
    return {"resolution_s": round(1 / fps, 3), "frames": n, "cuts": [T(i) for i in cuts], "flashes": flashes,
            "blank_frames": blanks, "holds": holds[:15], "reappearances": recur,
            "reappearance_resolution_s": round(step / fps, 2),
            "pacing": {"cuts_per_min": round(len(cuts) / minutes, 1),
                       "longest_hold_s": holds[0]["s"] if holds else 0.0,
                       "still_fraction": round(float(still.mean()), 2)}}


def cmd_measure(a):
    video = resolve(a.video)
    os.makedirs(a.out, exist_ok=True)
    p = probe(video)
    words = load_words(a.transcript) if a.transcript else []
    vis = visual_measures(video, p)
    m = {"schema": "vqr-mechanical/1",
         "video": {"path": os.path.abspath(video), "sha256": sha256(video), **p},
         "audio_playback": "none — decoded to pipes and /dev/null only",
         "passes": {"M1": {"kind": "mechanical-video", "fps": p["fps"], "window": "full",
                           "resolution_s": vis["resolution_s"]}},
         "visual": vis,
         "audio": None}
    if p["has_audio"]:
        m["audio"] = audio_measures(video, vis["cuts"], words)
        m["passes"]["A1"] = {"kind": "audio", "tools": "loudnorm+envelope" + ("+transcript" if words else ""),
                             "resolution_s": 0.1}
    m["strips"] = []
    if not a.no_strips:
        d, f = os.path.join(a.out, "events"), 1 / p["fps"]
        os.makedirs(d, exist_ok=True)
        for k, e in enumerate(vis["flashes"][:12], 1):
            t0, t1 = e["t"]
            times = [t0 - 2 * f, t0 - f, t0, (t0 + t1) / 2, t1, t1 + f]
            m["strips"].append(strip(os.path.join(d, f"flash_{k:02d}.jpg"), [("", video, times)], cols=6))
        for k, e in enumerate(vis["reappearances"][:8], 1):
            (a0, a1), (b0, b1) = e["first"], e["again"]
            times = [a0, a1, (a1 + b0) / 2, b0, b1]
            m["strips"].append(strip(os.path.join(d, f"reappear_{k:02d}.jpg"), [("", video, times)], cols=5))
    path = os.path.join(a.out, "mechanical.json")
    json.dump(m, open(path, "w"), indent=1, ensure_ascii=False)
    au = m["audio"] or {}
    print(f"wrote: {path}")
    print(f"video: {p['width']}x{p['height']} ({p['aspect']}) {p['duration_s']}s @ {p['fps']} fps")
    print(f"visual: {len(vis['cuts'])} hard cuts · {len(vis['flashes'])} flash/blink events · "
          f"{len(vis['reappearances'])} reappearances · {len(vis['blank_frames'])} blank runs · "
          f"longest hold {vis['pacing']['longest_hold_s']}s")
    if au:
        print(f"audio: {au['integrated_lufs']} LUFS · TP {au['true_peak_dbtp']} dBTP · "
              f"{len(au['dead_air'])} dead-air runs · "
              f"{sum(1 for c in au['cuts'] if abs(c['step_db'] or 0) >= 20)} cuts with a hard audio edge")
        if not words:
            print("audio: no transcript given — speech gaps, orphan sounds and words at cuts were NOT measured")
    print(f"strips: {len(m['strips'])} in {os.path.join(a.out, 'events')}" if m["strips"] else "strips: none")
    print("audio playback: none")


# ---------------------------------------------------------------- frames, sheets, strips

def seek(t):
    # Floor to the millisecond: rounding up would skip to the next frame.
    return f"{math.floor(max(t, 0) * 1000) / 1000:.3f}"


def grab(video, t, width, crop=None):
    from PIL import Image
    vf = ([f"crop=iw*{crop[2]}:ih*{crop[3]}:iw*{crop[0]}:ih*{crop[1]}"] if crop else []) + [f"scale={width}:-2"]
    out = sh(["ffmpeg", "-v", "error", "-ss", seek(t), "-i", video, "-frames:v", "1",
              "-vf", ",".join(vf), "-f", "image2pipe", "-vcodec", "png", "-"]).stdout
    return Image.open(io.BytesIO(out)).convert("RGB") if out else None


def strip(out, rows, cols=None, width=360, crop=None):
    """One labelled image. rows = [(label, video, [t, ..])]; every tile carries its real timestamp."""
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.load_default(size=18)
    tiles = [(f"{label} {clock(t)}".strip(), grab(video, t, width, crop)) for label, video, ts in rows for t in ts]
    tiles = [(lab, im) for lab, im in tiles if im]
    if not tiles:
        die("no frames at those times")
    cols = cols or max(len(ts) for _, _, ts in rows)
    th = max(im.height for _, im in tiles) + 24
    sheet = Image.new("RGB", (cols * width, th * math.ceil(len(tiles) / cols)), (20, 20, 20))
    draw = ImageDraw.Draw(sheet)
    for k, (lab, im) in enumerate(tiles):
        x, y = (k % cols) * width, (k // cols) * th
        sheet.paste(im, (x, y + 24))
        draw.text((x + 4, y + 2), lab, fill=(255, 255, 0), font=font)
    sheet.save(out, quality=90)
    return out


def parse_crop(s):
    return [float(x) for x in s.split(":")] if s else None


def cmd_strip(a):
    rows = []
    for spec in a.specs:
        m = re.match(r"(?:([^=]*)=)?(.+)@([\d.,:]+)$", spec)
        if not m:
            die(f"bad spec {spec!r} — want LABEL=VIDEO@T,T,..")
        rows.append((m.group(1) or "", resolve(m.group(2)), [to_seconds(t) for t in m.group(3).split(",")]))
    print("wrote:", strip(a.out, rows, cols=a.cols, width=a.width, crop=parse_crop(a.crop)))
    for label, _, ts in rows:
        print(f"row {label or '-'}: " + " ".join(clock(t) for t in ts))


def to_seconds(s):
    parts = [float(x) for x in str(s).split(":")]
    return sum(x * 60 ** k for k, x in enumerate(reversed(parts)))


def sample_times(a, duration):
    if a.at:
        return [to_seconds(t) for t in a.at.split(",")]
    lo, hi = a.start or 0.0, min(a.to or duration, duration)
    gap = 1 / a.fps if a.fps else a.every
    # Midpoints of each interval — the same instants ffmpeg's fps filter shows, named honestly.
    return [round(lo + (k + 0.5) * gap, 3) for k in range(int((hi - lo) / gap + 1e-6))]


def cmd_frames(a):
    video = resolve(a.video)
    p = probe(video)
    os.makedirs(a.dir, exist_ok=True)
    width = a.width or min(p["width"], 1960)
    names = []
    for t in sample_times(a, p["duration_s"]):
        name = os.path.join(a.dir, f"{a.prefix}_t{t:07.2f}.jpg")
        sh(["ffmpeg", "-v", "error", "-y", "-ss", seek(t), "-i", video, "-frames:v", "1",
            "-vf", f"scale={width}:-2", "-q:v", "2", name])
        if os.path.exists(name):
            names.append(name)
    print(f"dir: {a.dir}")
    print(f"frames: {len(names)} · names carry the real timestamp in seconds ({a.prefix}_t0083.50.jpg = 01:23.50)")
    if names:
        print(f"first: {os.path.basename(names[0])} · last: {os.path.basename(names[-1])}")


def cmd_sheet(a):
    video = resolve(a.video)
    p = probe(video)
    os.makedirs(a.dir, exist_ok=True)
    cols = a.cols or (6 if p["height"] > p["width"] else 4)
    a.at = a.fps = a.start = a.to = None
    times, per = sample_times(a, p["duration_s"]), cols * a.rows
    for k in range(0, len(times), per):
        chunk = times[k:k + per]
        out = strip(os.path.join(a.dir, f"sheet_{k // per + 1:02d}.jpg"), [("", video, chunk)], cols=cols, width=a.width)
        print(f"{out}: {clock(chunk[0])} – {clock(chunk[-1])} ({len(chunk)} tiles)")


# ---------------------------------------------------------------- align

STOP = set("para como pero este esta estos estas esto with that this from sobre entre desde cuando donde porque "
           "tiene tienen todo todos toda todas mas muy pero cada otro otra otros otras solo ellos ellas "
           "they them their there have has were what when which will your about into than then also".split())


def norm(s):
    s = unicodedata.normalize("NFKD", s.lower())
    return re.sub(r"[^a-z0-9 ]", " ", "".join(c for c in s if not unicodedata.combining(c)))


def tokens(text):
    return [t for t in norm(text).split() if (len(t) >= 4 and t not in STOP) or t.isdigit()]


def same_word(a, b):
    if a.isdigit() or b.isdigit():
        return a == b
    k = min(len(a), len(b), 6)
    return k >= 4 and a[:k] == b[:k]                     # tolerate inflection: restricción / restricciones


def align(words, shown, tol=2.0):
    spoken = [(norm(w[0]).strip(), w[1], w[2], w[0]) for w in words]
    out = []
    for o in shown:
        t0, t1 = float(o["t0"]), float(o.get("t1", o["t0"]))
        toks = tokens(o["text"])
        said = {t: [s[1] for s in spoken if s[0] and same_word(t, s[0])] for t in toks}
        said = {t: h for t, h in said.items() if h}
        # Where the voice is on this text: the moments when most of its words are said together
        # (within 3 s). One shared word — "NVIDIA" — said elsewhere does not count as a mention.
        every = sorted(h for hs in said.values() for h in hs)
        cover = [sum(any(abs(x - h) <= 3 for x in hs) for hs in said.values()) for h in every]
        hits = [h for h, c in zip(every, cover) if c == max(cover)]
        row = {"t": [t0, t1], "text": o["text"], "words_matched": f"{max(cover, default=0)}/{len(toks)}",
               "spoken_in_slot": " ".join(s[3] for s in spoken if s[2] > t0 and s[1] < t1)}
        if not toks:
            row["status"] = "no-content-words"
        elif not hits:
            row["status"] = "never-spoken"
        elif any(t0 - tol <= h <= t1 + tol for h in hits):
            row["status"] = "in-slot"
        else:
            near = min(hits, key=lambda h: min(abs(h - t0), abs(h - t1)))
            row["status"], row["offset_s"] = ("early", round(near - t1, 1)) if near > t1 else ("late", round(t0 - near, 1))
            k = min(range(len(spoken)), key=lambda i: abs(spoken[i][1] - near))
            row["nearest_mention"] = {"t": spoken[k][1],
                                      "quote": " ".join(s[3] for s in spoken[max(0, k - 4):k + 5])}
        out.append(row)
    return out


def cmd_align(a):
    rows = align(load_words(a.transcript), json.load(open(a.onscreen)), a.tol)
    if a.out:
        json.dump(rows, open(a.out, "w"), indent=1, ensure_ascii=False)
    for r in rows:
        if r["status"] in ("early", "late"):
            print(f"{r['status']:13} {r['offset_s']:5}s  {clock(r['t'][0])}  {r['text']!r} — spoken at "
                  f"{clock(r['nearest_mention']['t'])}; meanwhile the voice says: {r['spoken_in_slot']!r}")
        elif r["status"] == "never-spoken":
            print(f"never-spoken          {clock(r['t'][0])}  {r['text']!r} — meanwhile: {r['spoken_in_slot']!r}")
    n = {s: sum(1 for r in rows if r["status"] == s) for s in ("in-slot", "early", "late", "never-spoken")}
    print(f"{len(rows)} on-screen texts: {n}. These are candidates, not findings — see SKILL.md §D4.")


# ---------------------------------------------------------------- check

def derive_verdict(findings):
    s4 = [f for f in findings if f.get("severity") == 4]
    s3_dims = {f.get("dim") for f in findings if f.get("severity") == 3}
    return "DO NOT SHIP" if s4 or len(s3_dims) >= 3 else "SHIP WITH FIXES" if s3_dims else "SHIP"


def check_report(r):
    err, warn = [], []
    for key in ("label", "video", "request", "passes", "audio_playback", "transcript", "verdict", "levels",
                "findings", "positives", "not_scored", "coverage", "escalate"):
        if key not in r:
            err.append(f"missing top-level key: {key}")
    if err:
        return err, warn
    if not str(r["audio_playback"]).lower().startswith("none"):
        err.append("audio_playback must start with 'none' — this review never plays audio")
    if not any("listening" in str(x).lower() for x in r["not_scored"]):
        err.append("not_scored must declare that subjective listening was not performed")
    passes = r["passes"]
    for name, p in passes.items():
        if not isinstance(p.get("resolution_s"), (int, float)):
            err.append(f"pass {name}: resolution_s missing")
    for d in ("D1", "D2", "D3", "D4", "D5", "D6"):
        lv = str(r["levels"].get(d, ""))
        if lv not in LEVELS and not lv.startswith("NOT SCORED"):
            err.append(f"levels.{d}: {lv!r} is not one of {LEVELS} or 'NOT SCORED — <reason>'")
    for f in r["findings"]:
        fid = f.get("id", "?")
        for key in ("id", "dim", "class", "severity", "f", "i", "p_s", "t", "pass", "region", "kind",
                    "confidence", "evidence", "expected", "verified_by_judge"):
            if key not in f:
                err.append(f"{fid}: missing {key}")
        if any(k not in f for k in ("severity", "t", "pass", "evidence", "i", "kind", "confidence")):
            continue
        sev, res = f["severity"], passes.get(f["pass"], {}).get("resolution_s")
        if res is None:
            err.append(f"{fid}: pass {f['pass']!r} is not declared in passes (one label, the pass that located it)")
            continue
        if not (isinstance(f["t"], list) and len(f["t"]) == 2 and f["t"][1] - f["t"][0] >= res - 1e-6):
            err.append(f"{fid}: t={f['t']} is narrower than {f['pass']}'s resolution ({res}s) — widen it to an interval")
        text = f"{f['evidence']} {f.get('expected', '')}"
        for tag, tok in re.findall(r"(?:\b(\w+)@)?(\d{1,2}:\d{2}(?:\.\d+)?)", text):
            if tag not in passes:
                err.append(f"{fid}: time {tok} in the prose has no pass tag — write it as PASS@{tok}")
        for dec in re.findall(r"(?<![\d:@])\d+\.(\d+) ?s\b", text):
            if 10 ** -len(dec) < res / 5:
                err.append(f"{fid}: a duration with {len(dec)} decimals is finer than {f['pass']} ({res}s) can support")
        if f["kind"] not in ("measured", "judged"):
            err.append(f"{fid}: kind must be measured|judged")
        if f["confidence"] not in ("high", "medium", "low"):
            err.append(f"{fid}: confidence must be high|medium|low")
        if f["i"] not in ("cosmetic", "attention", "comprehension", "trust"):
            err.append(f"{fid}: i must be cosmetic|attention|comprehension|trust")
        if f.get("f") not in ("once", "recurring", "throughout"):
            err.append(f"{fid}: f must be once|recurring|throughout")
        if sev not in (1, 2, 3, 4):
            err.append(f"{fid}: severity must be 1-4")
            continue
        if f["i"] == "cosmetic" and sev > 2:
            err.append(f"{fid}: S{sev} with i:cosmetic contradicts itself")
        if sev == 4 and (f["i"] not in ("comprehension", "trust") or f.get("s4_reason") not in S4_REASONS):
            err.append(f"{fid}: S4 needs i:comprehension|trust and s4_reason in {S4_REASONS}")
        if sev >= 3 and not f.get("verified_by_judge"):
            err.append(f"{fid}: S{sev} must be verified on the source frames by the judge")
        if sev >= 3 and f["confidence"] == "low":
            err.append(f"{fid}: low confidence caps severity at S2 — verify it or lower it, and list it in escalate")
        regions = {c for part in str(f["region"]).split(",") for c in [part.strip()]}
        if not regions & (set(CELLS) | {"full-frame", "audio"}):
            err.append(f"{fid}: region must use the 3x3 vocabulary, 'full-frame' or 'audio'")
        if len(str(f["evidence"])) < 15:
            err.append(f"{fid}: evidence too thin — quote what is on screen or in the audio, verbatim")
    want = derive_verdict(r["findings"])
    if r["verdict"] != want:
        err.append(f"verdict is {r['verdict']!r} but the findings derive {want!r} — the verdict is computed, not chosen")
    if not 2 <= len(r["positives"]) <= 5:
        err.append(f"positives: need 2-5, got {len(r['positives'])}")
    for d in ("D1", "D2", "D3", "D4", "D5", "D6"):
        worst = max([f.get("severity", 0) for f in r["findings"] if f.get("dim") == d] or [0])
        if worst >= 3 and r["levels"].get(d) in ("Clean", "Rough"):
            warn.append(f"{d} is {r['levels'][d]} but holds an S{worst} finding — reread the anchored levels")
    ids = {f.get("id") for f in r["findings"]}
    for f in r["findings"]:
        if f.get("severity") == 4 and f.get("id") not in r["escalate"]:
            warn.append(f"{f.get('id')}: every S4 belongs in escalate")
    for e in r["escalate"]:
        if e not in ids:
            err.append(f"escalate names {e!r}, which is not a finding id")
    return err, warn


def check_family(fam):
    err = []
    known = {v["label"]: set(v["finding_ids"]) for v in fam.get("videos", [])}
    for k, d in enumerate(fam.get("differences", []), 1):
        for key in ("statement", "videos", "evidence", "kind", "confidence"):
            if key not in d:
                err.append(f"difference {k}: missing {key}")
        for ref in d.get("evidence", []):
            label, _, fid = ref.partition(":")
            if fid not in known.get(label, set()) and not ref.startswith("table:"):
                err.append(f"difference {k}: evidence {ref!r} is not LABEL:FINDING_ID of a frozen report, nor table:<column>")
        if len(d.get("videos", [])) < 2:
            err.append(f"difference {k}: a difference names at least two videos")
    return err, []


def cmd_check(a):
    r = json.load(open(a.report))
    err, warn = check_family(r) if r.get("schema", "").startswith("vqr-family") else check_report(r)
    for w in warn:
        print("WARN ", w)
    for e in err:
        print("FAIL ", e)
    print(f"{'FAIL' if err else 'PASS'}: {len(err)} errors, {len(warn)} warnings — {a.report}")
    sys.exit(1 if err else 0)


# ---------------------------------------------------------------- compare

def corr(a, b):
    n = min(len(a), len(b))
    if n < 50 or abs(len(a) - len(b)) > 10:
        return None
    a, b = a[:n], b[:n]
    ma, mb = sum(a) / n, sum(b) / n
    va, vb = sum((x - ma) ** 2 for x in a), sum((y - mb) ** 2 for y in b)
    return sum((x - ma) * (y - mb) for x, y in zip(a, b)) / math.sqrt(va * vb) if va and vb else None


def cmd_compare(a):
    vids = []
    for d in a.dirs:
        r, m = json.load(open(os.path.join(d, "report.json"))), json.load(open(os.path.join(d, "mechanical.json")))
        f, vis, au = r["findings"], m["visual"], m.get("audio") or {}
        mins = m["video"]["duration_s"] / 60
        vids.append({"label": r["label"], "dir": d, "report_sha256": sha256(os.path.join(d, "report.json")),
                     "verdict": r["verdict"], "levels": r["levels"],
                     "counts": {f"S{s}": sum(1 for x in f if x["severity"] == s) for s in (4, 3, 2, 1)},
                     "s3plus_per_min": round(sum(1 for x in f if x["severity"] >= 3) / mins, 2),
                     "classes": sorted({x["class"] for x in f}),
                     "finding_ids": [x["id"] for x in f] + [g.get("id") for g in r["positives"]],
                     "measured": {"duration_s": m["video"]["duration_s"], "aspect": m["video"]["aspect"],
                                  "lufs": au.get("integrated_lufs"), "true_peak": au.get("true_peak_dbtp"),
                                  "cuts_per_min": vis["pacing"]["cuts_per_min"],
                                  "longest_hold_s": vis["pacing"]["longest_hold_s"],
                                  "flash_events": len(vis["flashes"]),
                                  "blank_runs_mid": sum(1 for b in vis["blank_frames"] if b["position"] == "middle"),
                                  "longest_speech_gap_s": max([g["s"] for g in au.get("speech_gaps", [])] or [0])},
                     "_env": au.get("envelope_100ms_db", []),
                     "_plan": {k: {x: y for x, y in p.items() if x not in ("frames", "window")}
                               for k, p in r["passes"].items()}})
    if len({v["label"] for v in vids}) != len(vids):
        die("labels must be unique across the family")
    same_audio = []
    for i, x in enumerate(vids):
        for y in vids[i + 1:]:
            c = corr(x["_env"], y["_env"])
            if c is not None and c >= 0.97:
                same_audio.append({"videos": [x["label"], y["label"]], "envelope_r": round(c, 3)})
    rank = sorted(vids, key=lambda v: (VERDICTS.index(v["verdict"]), v["counts"]["S4"], v["counts"]["S3"], v["counts"]["S2"]))
    order, prev = [], None
    for v in rank:
        key = (v["verdict"], v["counts"]["S4"], v["counts"]["S3"], v["counts"]["S2"])
        order[-1].append(v["label"]) if key == prev else order.append([v["label"]])
        prev = key
    classes = sorted({c for v in vids for c in v["classes"]})
    fam = {"schema": "vqr-family/1", "videos": [{k: x for k, x in v.items() if k[0] != "_"} for v in vids],
           "same_plan": all(v["_plan"] == vids[0]["_plan"] for v in vids),
           "same_audio": same_audio,
           "class_matrix": {c: [v["label"] for v in vids if c in v["classes"]] for c in classes},
           "ordering": order, "ordering_rule": "verdict, then S4, S3, S2 counts; labels sharing a list are tied",
           "differences": []}
    json.dump(fam, open(a.out, "w"), indent=1, ensure_ascii=False)
    print("| video | verdict | D1 | D2 | D3 | D4 | D5 | D6 | S4/S3/S2/S1 | S3+/min | dur | LUFS | cuts/min | flashes |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for v in vids:
        c, ms = v["counts"], v["measured"]
        lv = " | ".join(str(v["levels"].get(d, "?")).replace("NOT SCORED", "NS").split(" —")[0] for d in ("D1", "D2", "D3", "D4", "D5", "D6"))
        print(f"| {v['label']} | {v['verdict']} | {lv} | {c['S4']}/{c['S3']}/{c['S2']}/{c['S1']} | {v['s3plus_per_min']} | "
              f"{ms['duration_s']}s | {ms['lufs']} | {ms['cuts_per_min']} | {ms['flash_events']} |")
    if not fam["same_plan"]:
        print("\nWARN: the reports declare different passes — a video looked at more closely shows more defects")
    print(f"\nordering (ties share a group): {order}")
    for s in same_audio:
        print(f"same audio track: {s['videos']} (envelope r={s['envelope_r']}) — D2 differences between them are not real")
    print(f"classes not shared by all: " + "; ".join(f"{c}→{ls}" for c, ls in fam["class_matrix"].items() if len(ls) < len(vids)))
    print(f"wrote: {a.out} — add the judged entries to 'differences', then run check on it")


# ---------------------------------------------------------------- transcribe, doctor

def cmd_transcribe(a):
    video = resolve(a.video)
    os.makedirs(a.out, exist_ok=True)
    engine = next((e for e in ("mlx_whisper", "whisper") if shutil.which(e)), None)
    if not engine:
        die("no ASR engine found (mlx_whisper or whisper). Install one, or pass the caller's transcript and "
            "report subtitle accuracy as NOT SCORED.")
    model = a.model or ("mlx-community/whisper-large-v3-turbo" if engine == "mlx_whisper" else "turbo")

    def asr(name, window, language):
        wav = os.path.join(a.out, f"{name}.wav")
        cut = ["-ss", str(window[0]), "-to", str(window[1])] if window else []
        sh(["ffmpeg", "-v", "error", "-y", *cut, "-i", video, "-vn", "-ac", "1", "-ar", "16000", wav])
        r = sh([engine, wav, "--model", model, "--word-timestamps", "True", "--condition-on-previous-text", "False",
                "--output-format", "json", "--output-dir", a.out] + (["--language", language] if language else []))
        out = os.path.join(a.out, f"{name}.json")
        if r.returncode or not os.path.exists(out):
            die(f"{engine} failed: {r.stderr.decode(errors='replace')[-400:]}")
        d = json.load(open(out))
        os.remove(out), os.remove(wav)
        return d

    d = asr("audio", None, a.language)
    dur = probe(video)["duration_s"]
    segs = [s for s in d["segments"] if s.get("words")]
    edges = [0.0] + [t for s in segs for t in (s["start"], s["end"])] + [dur]
    # Whisper drops whole stretches after music or another language. A long hole gets one more
    # pass on its own, language auto-detected, before anyone calls it silence.
    refilled = []
    for lo, hi in zip(edges[::2], edges[1::2]):
        if hi - lo < 4:
            continue
        w = asr("window", (lo, hi), None)
        found = [s for s in w["segments"] if s.get("words")]
        for s in found:
            for x in [s] + s["words"]:
                x["start"], x["end"] = round(x["start"] + lo, 2), round(x["end"] + lo, 2)
        segs += found
        refilled.append({"t": [round(lo, 2), round(hi, 2)], "language": w.get("language"),
                         "words": sum(len(s["words"]) for s in found)})
    segs.sort(key=lambda s: s["start"])
    dst = os.path.join(a.out, "transcript.json")
    json.dump({"engine": f"{engine} {model}", "language": d.get("language"), "refilled_windows": refilled,
               "segments": [{"start": s["start"], "end": s["end"], "text": s["text"], "words": s["words"]} for s in segs]},
              open(dst, "w"), indent=1, ensure_ascii=False)
    words = load_words(dst)
    print(f"wrote: {dst} ({len(words)} words, last ends {clock(words[-1][2])})")
    for r in refilled:
        print(f"hole {clock(r['t'][0])}–{clock(r['t'][1])} re-transcribed alone: {r['words']} words, language {r['language']}")
    print(f"engine: {engine} {model} — put this in the A1 pass header; it is the Whisper family")
    print("audio playback: none")


def cmd_doctor(_):
    ok = True
    for tool in ("ffmpeg", "ffprobe"):
        ok &= bool(shutil.which(tool))
        print(f"{tool:12} {shutil.which(tool) or 'MISSING (required)'}")
    for mod, need in (("numpy", "measure"), ("PIL", "sheet/strip")):
        try:
            __import__(mod)
            print(f"{mod:12} ok")
        except ImportError:
            ok = False
            print(f"{mod:12} MISSING (needed by {need}): python3 -m pip install {'pillow' if mod == 'PIL' else mod}")
    for tool in ("mlx_whisper", "whisper", "tesseract"):
        print(f"{tool:12} {shutil.which(tool) or 'not installed (optional)'}")
    print("audio out    never — vqr has no code path to an audio device")
    sys.exit(0 if ok else 1)


# ---------------------------------------------------------------- self-test

def cmd_self_test(_):
    import numpy as np
    tmp = tempfile.mkdtemp()
    try:
        w, h, fps = 320, 180, 30
        yy, xx = np.mgrid[0:h, 0:w]
        A = ((xx * 255 // w) * 0.6 + 40).astype(np.uint8)            # horizontal ramp
        B = ((yy * 255 // h) * 0.6 + 40).astype(np.uint8)[:, ::-1]   # vertical ramp
        frames = []
        for i in range(180):
            f = (A if i < 60 or 90 <= i < 165 else B if i < 90 else np.zeros_like(A)).copy()
            if i in (120, 121):
                f[10:60, 220:310] = 255                               # two-frame flash, top-right
            frames.append(np.stack([f] * 3, axis=-1))
        t = np.arange(6 * 8000) / 8000
        tone = (np.sin(2 * np.pi * 440 * t) * 3000).astype(np.int16)
        tone[int(2.0 * 8000):int(3.7 * 8000)] = 0                     # dead air 2.0–3.7 s
        open(f"{tmp}/a.raw", "wb").write(tone.tobytes())
        open(f"{tmp}/v.raw", "wb").write(np.stack(frames).tobytes())
        r = sh(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", str(fps),
                "-i", f"{tmp}/v.raw", "-f", "s16le", "-ar", "8000", "-ac", "1", "-i", f"{tmp}/a.raw",
                "-pix_fmt", "yuv420p", "-c:a", "aac", f"{tmp}/clip.mp4"])
        assert r.returncode == 0, r.stderr
        cmd_measure(argparse.Namespace(video=f"{tmp}/clip.mp4", out=f"{tmp}/out", transcript=None, no_strips=False))
        m = json.load(open(f"{tmp}/out/mechanical.json"))
        v, au = m["visual"], m["audio"]
        assert [round(c, 1) for c in v["cuts"]] == [2.0, 3.0, 5.5], v["cuts"]
        assert len(v["flashes"]) == 1 and v["flashes"][0]["frames"] == 2 and v["flashes"][0]["region"] == ["top-right"], v["flashes"]
        assert abs(v["flashes"][0]["t"][0] - 4.0) < 0.04, v["flashes"]
        assert len(v["reappearances"]) == 1 and v["reappearances"][0]["first"][0] == 0.0, v["reappearances"]
        assert abs(v["reappearances"][0]["again"][0] - 3.0) <= 0.5, v["reappearances"]
        assert v["blank_frames"] and v["blank_frames"][-1]["position"] == "end", v["blank_frames"]
        assert any(abs(d["t"][0] - 2.0) < 0.1 for d in au["dead_air"]), au["dead_air"]
        assert len(m["strips"]) == 2 and all(os.path.getsize(s) > 1000 for s in m["strips"])

        words = [{"word": w_, "start": s, "end": s + 0.4} for w_, s in
                 [("hoy", 0.0), ("hablamos", 0.5), ("de", 1.0), ("chips", 1.2), ("y", 20.0), ("tres", 20.3), ("finales", 20.8)]]
        json.dump(words, open(f"{tmp}/t.json", "w"))
        rows = align(load_words(f"{tmp}/t.json"), [{"t0": 1.0, "t1": 3.0, "text": "CHIPS"},
                                                   {"t0": 5.0, "t1": 7.0, "text": "TRES FINALES"},
                                                   {"t0": 9.0, "t1": 9.0, "text": "compiten de cerca"}])
        assert [r_["status"] for r_ in rows] == ["in-slot", "early", "never-spoken"], rows
        assert rows[1]["offset_s"] == 13.3, rows[1]

        good = {"id": "F01", "dim": "D4", "class": "out-of-slot", "severity": 3, "f": "once", "i": "comprehension",
                "p_s": 6, "t": [31.0, 33.0], "pass": "P1", "region": "center", "kind": "judged", "confidence": "high",
                "evidence": 'heading "TRES FINALES" (P1@00:32) while A1@00:29.8 says "tenía 35 años"',
                "expected": "the graphic matches the clause in its own slot", "verified_by_judge": True}
        rep = {"label": "V1", "video": {}, "request": {}, "audio_playback": "none", "transcript": {},
               "passes": {"P1": {"resolution_s": 2.0}, "A1": {"resolution_s": 0.1}},
               "verdict": "SHIP WITH FIXES", "levels": {d: "Clean" for d in ("D1", "D2", "D3", "D5", "D6")} | {"D4": "Distracting"},
               "findings": [good], "positives": [{}, {}], "not_scored": ["prosody — subjective listening not performed"],
               "coverage": {}, "escalate": []}
        assert check_report(rep) == ([], []), check_report(rep)
        bad = dict(good, t=[31.0, 31.5], evidence="heading appears 0.83s ahead at 00:31.3", confidence="low")
        errs, _ = check_report(dict(rep, findings=[bad], verdict="SHIP"))
        assert len(errs) == 5, errs      # narrow interval, untagged time, fine duration, low-confidence S3, wrong verdict
        print("PASS: vqr self-test")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("doctor"); s.set_defaults(fn=cmd_doctor)
    s = sub.add_parser("transcribe"); s.set_defaults(fn=cmd_transcribe)
    s.add_argument("video"); s.add_argument("--out", required=True); s.add_argument("--language"); s.add_argument("--model")
    s = sub.add_parser("measure"); s.set_defaults(fn=cmd_measure)
    s.add_argument("video"); s.add_argument("--out", required=True); s.add_argument("--transcript")
    s.add_argument("--no-strips", action="store_true")
    s = sub.add_parser("frames"); s.set_defaults(fn=cmd_frames)
    s.add_argument("video"); s.add_argument("dir"); s.add_argument("--every", type=float, default=2.0)
    s.add_argument("--fps", type=float); s.add_argument("--from", dest="start", type=float); s.add_argument("--to", type=float)
    s.add_argument("--at"); s.add_argument("--width", type=int); s.add_argument("--prefix", default="f")
    s = sub.add_parser("sheet"); s.set_defaults(fn=cmd_sheet)
    s.add_argument("video"); s.add_argument("dir"); s.add_argument("--every", type=float, default=2.0)
    s.add_argument("--cols", type=int); s.add_argument("--rows", type=int, default=3); s.add_argument("--width", type=int, default=320)
    s = sub.add_parser("strip"); s.set_defaults(fn=cmd_strip)
    s.add_argument("out"); s.add_argument("specs", nargs="+"); s.add_argument("--cols", type=int)
    s.add_argument("--width", type=int, default=360); s.add_argument("--crop", help="x:y:w:h as fractions, e.g. 0:0.7:1:0.3")
    s = sub.add_parser("align"); s.set_defaults(fn=cmd_align)
    s.add_argument("transcript"); s.add_argument("onscreen"); s.add_argument("--tol", type=float, default=2.0); s.add_argument("--out")
    s = sub.add_parser("check"); s.set_defaults(fn=cmd_check); s.add_argument("report")
    s = sub.add_parser("compare"); s.set_defaults(fn=cmd_compare)
    s.add_argument("dirs", nargs="+"); s.add_argument("--out", required=True)
    s = sub.add_parser("self-test"); s.set_defaults(fn=cmd_self_test)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
