#!/usr/bin/env python3
"""Render mac-doctor's last run as one self-contained HTML page.

Reads ~/.claude/mac-doctor-last.txt (every doctor.sh run writes it), the trend
history, and a live CPU/RAM probe taken now. Writes
~/.claude/mac-doctor-report/index.html and prints its path.

The page lists every ACTION as a decision the viewer can tick. Ticks are kept in
the artifact's `db` capability (collection `actions`, one doc per action, field
`runId` scopes them to this run); the agent reads the ticked ones, applies them
and writes the outcome back to the same doc, which the page shows live.
Stdlib only.
"""
import hashlib
import html
import json
import re
import subprocess
import time
from pathlib import Path

HOME = Path.home()
LAST = HOME / ".claude/mac-doctor-last.txt"
HIST = HOME / ".claude/mac-doctor-history.tsv"
OUT = HOME / ".claude/mac-doctor-report/index.html"

esc = html.escape


def gb(s):
    """'19.53GB' / '488MB' / '719Gi' / '8.7GB' -> GB as float (None if unparseable)."""
    m = re.match(r"\s*([\d.]+)\s*([kKMGT]?)", s or "")
    if not m:
        return None
    return float(m.group(1)) * {"": 1e-9, "k": 1e-6, "K": 1e-6, "M": 1e-3, "G": 1, "T": 1e3}[m.group(2)]


def run(cmd, timeout=30):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""


# ---------- parse the doctor's own output format ----------
def parse_last(text):
    d = {"findings": [], "info": [], "docker": [], "ram_apps": [], "trend": [], "flagged_pids": set()}
    section = None
    last_item = None     # the FINDING/INFO an ACTION belongs to
    last_action = None   # an indented line right after an ACTION is its command
    for line in text.splitlines():
        if m := re.match(r"== mac-doctor (.+) ==", line):
            d["ran_at"] = m.group(1)
            continue
        if line.startswith(("DOCKER disk:", "DOCKER top RAM:", "HOST RAM by app")):
            section = line.split(":")[0].split(" (")[0]
            last_action = None
            continue
        if m := re.match(r"\s+ACTION: (.*)", line):
            last_action = parse_action(m.group(1), last_item)
            if last_item is not None:
                last_item["actions"].append(last_action)
            continue
        if last_action is not None and re.match(r" {4,}\S", line) and not last_action["command"]:
            last_action["command"] = line.strip()
            last_action["id"] = action_id(last_action)
            last_action["selectable"] = "<" not in last_action["command"]
            continue
        last_action = None
        if m := re.match(r"(FINDING|INFO): (.*)", line):
            item = {"text": m.group(2), "actions": []}
            (d["findings"] if m.group(1) == "FINDING" else d["info"]).append(item)
            last_item = item
            d["flagged_pids"].update(re.findall(r"pid=(\d+)", m.group(2)))
            section = None
            continue
        if section == "DOCKER disk" and (m := re.match(r"\s+(.+?)\t(\S+)\t(\S+)", line)):
            d["docker"].append((m.group(1), gb(m.group(2)), gb(m.group(3))))
            continue
        if section == "HOST RAM by app" and (m := re.match(r"\s+([\d.]+)GB (.+?)\s+n=(\d+)", line)):
            d["ram_apps"].append((m.group(2), float(m.group(1)), int(m.group(3))))
            continue
        if not line.startswith(" "):
            section = None
        if m := re.match(r"SWAP: total = ([\d.]+)M\s+used = ([\d.]+)M", line):
            d["swap"] = (float(m.group(2)) / 1024, float(m.group(1)) / 1024)
        elif m := re.match(r"VM disk: guest / (\d+)/(\d+)GB \((\d+)%\), host diffdisk (\d+)GB", line):
            d["vmdisk"] = tuple(int(x) for x in m.groups())
        elif m := re.match(r"DISK: (\S+) used / (\S+) \((\S+) free, (\d+)%\)", line):
            d["disk"] = (gb(m.group(1)), gb(m.group(2)), gb(m.group(3)), int(m.group(4)))
        elif m := re.match(r"COLIMA alloc: (.*)", line):
            d["colima"] = m.group(1)
        elif m := re.match(r"VM: pid=\d+ ram=(\d+)GB cpu=([\d.]+)%", line):
            d["vm"] = (int(m.group(1)), float(m.group(2)))
        elif line.startswith("TREND: "):
            d["trend"].append(line[7:])
    return d


def action_id(a):
    return "a-" + hashlib.sha1((a["command"] or a["title"]).encode()).hexdigest()[:12]


def parse_action(raw, item):
    sudo = raw.startswith("[SUDO]")
    body = raw.replace("[SUDO]", "", 1).strip()
    command, note = body, ""
    if m := re.match(r"(.*?)\s{2,}# (.*)", body):
        command, note = m.group(1), m.group(2)
    command = re.sub(r"^(run|investigate): ", "", command)
    # Prose ("cap every project...", "truncate it (...)") is a description, not a command.
    looks_cmd = re.match(r"(sudo |kill |docker |colima |sed |ps |~/|\./)", command)
    a = {"finding": item["text"] if item else "", "title": note or command if looks_cmd else body,
         "command": command if looks_cmd else "", "note": "", "sudo": sudo}
    a["id"] = action_id(a)
    # Placeholders (<vol>, <file>) need a human to fill them: shown, not tickable.
    a["selectable"] = "<" not in (a["command"] or "") and not a["title"].startswith("if ")
    return a


# ---------- live probes (taken now, labelled as such) ----------
def cpu_probe():
    out = run(["top", "-l", "2", "-s", "1", "-n", "12", "-o", "cpu", "-stats", "pid,command,cpu"])
    block = out.split("Processes:")[-1] if "Processes:" in out else ""
    cpu = re.search(r"CPU usage: ([\d.]+)% user, ([\d.]+)% sys, ([\d.]+)% idle", block)
    load = re.search(r"Load Avg: ([\d.]+), ([\d.]+), ([\d.]+)", block)
    procs, started = [], False
    for line in block.splitlines():
        if line.startswith("PID"):
            started = True
            continue
        parts = line.split()
        if started and len(parts) >= 3:
            try:
                procs.append((parts[0], " ".join(parts[1:-1]), float(parts[-1])))
            except ValueError:
                pass
    return {"usage": tuple(map(float, cpu.groups())) if cpu else None,
            "load": tuple(map(float, load.groups())) if load else None,
            "procs": [p for p in procs if p[2] > 0.5][:10]}


def mem_probe():
    total = int(run(["sysctl", "-n", "hw.memsize"]) or 0) / 1073741824
    vs = run(["vm_stat"])
    page = int((re.search(r"page size of (\d+)", vs) or [0, 16384])[1])
    pages = {k.strip(): int(v.strip(" .")) for k, v in re.findall(r'^"?([^:]+?)"?:\s+(\d+)\.', vs, re.M)}
    g = lambda *ks: sum(pages.get(k, 0) for k in ks) * page / 1073741824
    if not pages or not total:
        return None
    seg = [("Wired (sistema)", g("Pages wired down"), "s1"),
           ("Apps y caché", g("Pages active", "Pages inactive"), "s2"),
           ("Comprimida", g("Pages occupied by compressor"), "s3"),
           ("Libre", g("Pages free", "Pages speculative"), "idle")]
    return {"total": total, "segments": seg}


def history():
    try:
        rows = [r.split("\t") for r in HIST.read_text().splitlines()[1:] if r.strip()]
    except OSError:
        return []
    out = []
    for r in rows:
        try:
            out.append((int(r[0]), r[1], float(r[2]), float(r[4]) if r[4] else None))
        except (ValueError, IndexError):
            pass
    return out


# ---------- rendering helpers ----------
ICONS = {
    "cpu": '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
    "ram": '<rect x="3" y="7" width="18" height="10" rx="1.5"/><path d="M7 7v10M11 7v10M15 7v10M5 17v3M19 17v3"/>',
    "disk": '<ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>',
    "box": '<path d="M3 7.5 12 3l9 4.5v9L12 21l-9-4.5z"/><path d="M3 7.5 12 12l9-4.5M12 12v9"/>',
    "trend": '<path d="M3 17l6-6 4 4 8-8"/><path d="M15 7h6v6"/>',
    "alert": '<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17.5v.5"/>',
    "info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>',
    "check": '<path d="M4 12.5 9.5 18 20 6"/>',
    "term": '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="m7 9 3 3-3 3M13 15h4"/>',
    "send": '<path d="M4 12 20 4l-6 16-3-7z"/>',
}


def icon(name, cls="ic"):
    return f'<svg class="{cls}" viewBox="0 0 24 24" aria-hidden="true">{ICONS[name]}</svg>'


def status(level):
    label = {"ok": "Bien", "warn": "Atención", "crit": "Crítico", "na": "Sin datos"}[level]
    ic = {"ok": "check", "warn": "alert", "crit": "alert", "na": "info"}[level]
    return f'<span class="chip {level}">{icon(ic, "ic sm")}{label}</span>'


def lvl(v, warn, crit):
    return "na" if v is None else "crit" if v >= crit else "warn" if v >= warn else "ok"


def stack(segments, unit="GB", fmt="{:.1f}"):
    """One 100% bar of named segments + legend. segments: (label, value, token)."""
    total = sum(v for _, v, _ in segments) or 1
    bars = "".join(
        f'<span class="seg" style="flex:{v:.4f};background:var(--{t})" title="{esc(l)}: {fmt.format(v)} {unit}"></span>'
        for l, v, t in segments if v > 0)
    legend = "".join(
        f'<li><i style="background:var(--{t})"></i>{esc(l)} <b>{fmt.format(v)} {unit}</b> <span>{v / total:.0%}</span></li>'
        for l, v, t in segments)
    return f'<div class="stack">{bars}</div><ul class="legend">{legend}</ul>'


def hbars(rows, unit, ref=None, ref_label=""):
    """Horizontal bars: rows = (label, value, flagged, extra). Scale = max(value, ref)."""
    if not rows:
        return '<p class="empty">Sin datos en esta ejecución.</p>'
    top = max([r[1] for r in rows] + [ref or 0]) or 1
    out = []
    for label, v, flagged, extra in rows:
        tag = f'<span class="flag">{icon("alert", "ic sm")}hallazgo</span>' if flagged else ""
        out.append(
            f'<div class="hb{" flagged" if flagged else ""}" title="{esc(label)}: {v:.1f}{unit}">'
            f'<span class="hb-l">{esc(label)}{tag}</span>'
            f'<span class="hb-t"><span class="hb-b" style="width:{v / top * 100:.2f}%"></span>'
            + (f'<span class="hb-ref" style="left:{ref / top * 100:.2f}%" title="{esc(ref_label)}"></span>' if ref else "")
            + f'</span><span class="hb-v">{v:.1f}{unit}{extra}</span></div>')
    note = f'<p class="axisnote"><span class="refkey"></span>{esc(ref_label)}</p>' if ref else ""
    return '<div class="hbars">' + "".join(out) + "</div>" + note


def meter(label, used, total, unit="GB", pct_override=None):
    pct = used / total if total else 0
    # df's own % counts reserved blocks; pass it so the meter agrees with the tile.
    level = lvl(pct_override if pct_override is not None else pct * 100, 80, 90)
    return (f'<div class="meter"><div class="meter-h"><span>{esc(label)}</span>'
            f'<b>{used:.0f} / {total:.0f} {unit}</b>{status(level)}</div>'
            f'<div class="meter-t"><span class="meter-b {level}" style="width:{pct * 100:.1f}%"></span></div></div>')


def trend_chart(hist):
    pts = [h for h in hist if h[3] is not None]
    if len(hist) < 2:
        return ('<p class="empty">Hace falta más de una ejecución del doctor para dibujar la tendencia. '
                'Cada ejecución añade una fila a <code>~/.claude/mac-doctor-history.tsv</code>.</p>')
    W, H, L, R, T, B = 640, 220, 44, 96, 14, 30
    xs = [h[0] for h in hist]
    x0, x1 = min(xs), max(xs) or 1
    series = [("Mac (usado)", [(h[0], h[2]) for h in hist], "s1"),
              ("VM de Docker (diffdisk)", [(h[0], h[3]) for h in pts], "s2")]
    vals = [v for _, s, _ in series for _, v in s]
    lo, hi = 0, max(vals) * 1.1
    sx = lambda x: L + (x - x0) / ((x1 - x0) or 1) * (W - L - R)
    sy = lambda y: T + (1 - (y - lo) / (hi - lo)) * (H - T - B)
    grid = ""
    for i in range(5):
        v = lo + (hi - lo) * i / 4
        grid += (f'<line x1="{L}" x2="{W - R}" y1="{sy(v):.1f}" y2="{sy(v):.1f}" class="grid"/>'
                 f'<text x="{L - 6}" y="{sy(v) + 4:.1f}" class="tick" text-anchor="end">{v:.0f}</text>')
    lines = ""
    for name, s, tok in series:
        if not s:
            continue
        path = " ".join(f"{'M' if i == 0 else 'L'}{sx(x):.1f},{sy(y):.1f}" for i, (x, y) in enumerate(s))
        lines += f'<path d="{path}" fill="none" stroke="var(--{tok})" stroke-width="2"/>'
        for x, y in s:
            lines += (f'<circle cx="{sx(x):.1f}" cy="{sy(y):.1f}" r="4" fill="var(--{tok})" stroke="var(--surface)" stroke-width="2">'
                      f'<title>{esc(name)}: {y:.0f} GB · {time.strftime("%d %b %H:%M", time.localtime(x))}</title></circle>')
        ex, ey = s[-1]
        lines += f'<text x="{sx(ex) + 8:.1f}" y="{sy(ey) + 4:.1f}" class="dl">{ey:.0f} GB</text>'
    first = time.strftime("%d %b %H:%M", time.localtime(x0))
    last = time.strftime("%d %b %H:%M", time.localtime(x1))
    axis = (f'<text x="{L}" y="{H - 8}" class="tick">{first}</text>'
            f'<text x="{W - R}" y="{H - 8}" class="tick" text-anchor="end">{last}</text>')
    legend = "".join(f'<li><i style="background:var(--{t})"></i>{esc(n)}</li>' for n, _, t in series)
    return (f'<ul class="legend">{legend}</ul><div class="scroll"><svg class="chart" viewBox="0 0 {W} {H}" role="img" '
            f'aria-label="GB usados en el Mac y en la VM de Docker a lo largo de {len(hist)} ejecuciones">'
            f'{grid}{axis}{lines}</svg></div>')


def findings_html(items, kind):
    if not items:
        return ""
    out = []
    for it in items:
        ic = "alert" if kind == "finding" else "info"
        out.append(f'<li class="{kind}">{icon(ic)}<span>{esc(it["text"])}</span></li>')
    return "".join(out)


# ---------- page ----------
def main():
    text = LAST.read_text() if LAST.exists() else ""
    d = parse_last(text)
    cpu, mem, hist = cpu_probe(), mem_probe(), history()
    host = run(["scutil", "--get", "ComputerName"]).strip() or "este Mac"
    run_id = f"r{int(LAST.stat().st_mtime) if LAST.exists() else int(time.time())}"
    ncpu = int(run(["sysctl", "-n", "hw.ncpu"]) or 1)

    actions = [a for f in d["findings"] + d["info"] for a in f["actions"]]
    seen, uniq = set(), []
    for a in actions:
        if a["id"] not in seen:
            seen.add(a["id"])
            uniq.append(a)

    # Status tiles: summary before detail.
    busy = 100 - cpu["usage"][2] if cpu["usage"] else None
    swap_pct = d["swap"][0] / d["swap"][1] * 100 if d.get("swap") else None
    disk_pct = d["disk"][3] if d.get("disk") else None
    vm_pct = d["vmdisk"][2] if d.get("vmdisk") else None
    tiles = [
        ("cpu", "CPU", f"{busy:.0f}%" if busy is not None else "—", "ocupada ahora", lvl(busy, 60, 85)),
        ("ram", "Swap", f"{swap_pct:.0f}%" if swap_pct is not None else "—",
         f"{d['swap'][0]:.1f} de {d['swap'][1]:.0f} GB" if d.get("swap") else "sin datos", lvl(swap_pct, 50, 80)),
        ("disk", "Disco del Mac", f"{disk_pct}%" if disk_pct is not None else "—",
         f"{d['disk'][2]:.0f} GB libres" if d.get("disk") else "sin datos", lvl(disk_pct, 80, 90)),
        ("box", "Disco de la VM", f"{vm_pct}%" if vm_pct is not None else "—",
         f"{d['vmdisk'][0]} de {d['vmdisk'][1]} GB" if d.get("vmdisk") else "sin Colima", lvl(vm_pct, 80, 90)),
    ]
    tiles_html = "".join(
        f'<div class="tile {l}">{icon(i)}<div><p class="t-k">{esc(k)}</p><p class="t-v">{esc(v)}</p>'
        f'<p class="t-s">{esc(s)}</p></div>{status(l)}</div>' for i, k, v, s, l in tiles)

    # CPU detail
    if cpu["usage"]:
        u, s_, idle = cpu["usage"]
        cpu_stack = stack([("Usuario", u, "s1"), ("Sistema", s_, "s2"), ("Libre", idle, "idle")], "%", "{:.0f}")
    else:
        cpu_stack = '<p class="empty">No se pudo leer el uso de CPU.</p>'
    load = cpu["load"]
    load_html = (f'<p class="kv">Carga media (1 / 5 / 15 min): <b>{load[0]:.1f} · {load[1]:.1f} · {load[2]:.1f}</b> '
                 f'sobre {ncpu} núcleos</p>') if load else ""
    proc_rows = [(f"{name} ({pid})", v, pid in d["flagged_pids"], "") for pid, name, v in cpu["procs"]]
    cpu_bars = hbars(proc_rows, "%", ref=100, ref_label="100% = un núcleo completo")

    # RAM detail
    ram_stack = stack(mem["segments"]) if mem else '<p class="empty">No se pudo leer vm_stat.</p>'
    swap_meter = meter("Swap", d["swap"][0], d["swap"][1]) if d.get("swap") else ""
    app_rows = [(n, g, False, f' <span class="n">×{c}</span>') for n, g, c in d["ram_apps"]]
    ram_bars = hbars(app_rows, " GB")

    # Disk detail
    disk_meters = ""
    if d.get("disk"):
        disk_meters += meter("Disco del Mac", d["disk"][0], d["disk"][1], pct_override=d["disk"][3])
    if d.get("vmdisk"):
        disk_meters += meter("Disco de la VM de Docker", d["vmdisk"][0], d["vmdisk"][1], pct_override=d["vmdisk"][2])
        disk_meters += f'<p class="kv">El archivo de la VM ocupa <b>{d["vmdisk"][3]} GB</b> en el disco del Mac.</p>'
    names = {"Images": "Imágenes", "Containers": "Contenedores", "Local Volumes": "Volúmenes", "Build Cache": "Caché de build"}
    dk = ""
    top = max([r[1] or 0 for r in d["docker"]] + [1])
    for t, size, rec in d["docker"]:
        if size is None:
            continue
        rec = min(rec or 0, size)
        dk += (f'<div class="hb" title="{esc(names.get(t, t))}: {size:.1f} GB, {rec:.1f} GB recuperables">'
               f'<span class="hb-l">{esc(names.get(t, t))}</span><span class="hb-t">'
               f'<span class="hb-b" style="width:{(size - rec) / top * 100:.2f}%"></span>'
               f'<span class="hb-b rec" style="width:{rec / top * 100:.2f}%"></span></span>'
               f'<span class="hb-v">{size:.1f} GB</span></div>')
    docker_html = (('<ul class="legend"><li><i style="background:var(--s1)"></i>En uso</li>'
                    '<li><i style="background:var(--s2)"></i>Recuperable</li></ul><div class="hbars">' + dk + "</div>")
                   if dk else '<p class="empty">Docker no respondía en esta ejecución.</p>')

    trend_lines = "".join(f"<li>{esc(t)}</li>" for t in d["trend"])
    data = {"runId": run_id, "actions": uniq}
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")

    page = TEMPLATE
    for k, v in {
        "HOST": esc(host), "RAN_AT": esc(d.get("ran_at", "sin ejecución guardada")),
        "NOW": time.strftime("%Y-%m-%d %H:%M"), "TILES": tiles_html,
        "NFIND": str(len(d["findings"])), "NACT": str(len(uniq)),
        "CPU_STACK": cpu_stack, "LOAD": load_html, "CPU_BARS": cpu_bars,
        "RAM_STACK": ram_stack, "SWAP": swap_meter, "RAM_BARS": ram_bars,
        "COLIMA": f'<p class="kv">Colima: <b>{esc(d["colima"])}</b></p>' if d.get("colima") else "",
        "DISK": disk_meters, "DOCKER": docker_html,
        "TREND": trend_chart(hist), "TREND_LINES": f'<ul class="plain">{trend_lines}</ul>' if trend_lines else "",
        "FINDINGS": findings_html(d["findings"], "finding"), "INFO": findings_html(d["info"], "info"),
        "RAW": esc(text or "(vacío)"), "PAYLOAD": payload,
        "I_CPU": icon("cpu"), "I_RAM": icon("ram"), "I_DISK": icon("disk"), "I_BOX": icon("box"),
        "I_TREND": icon("trend"), "I_TERM": icon("term"), "I_ALERT": icon("alert"), "I_SEND": icon("send", "ic sm"),
        "I_CHECK": icon("check", "ic sm"),
    }.items():
        page = page.replace("{{" + k + "}}", v)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(page)
    # The agent's allowlist: only these ids/commands may be run, never text read back from the db.
    (OUT.parent / "actions.json").write_text(json.dumps(data, ensure_ascii=False, indent=1))
    print(OUT)
    print(f"runId={run_id} actions={len(uniq)} findings={len(d['findings'])}")


TEMPLATE = r"""<title>Pulso del Mac</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600&display=swap">
<style>
:root{
  --ground:#F2F4F7; --surface:#FFFFFF; --sunk:#E8EBF0; --line:#D8DDE4;
  --ink:#13171D; --ink-2:#4B5361; --ink-3:#7A8391;
  --s1:#2A78D6; --s2:#EB6834; --s3:#1BAF7A; --idle:#D5DAE1;
  --ok:#1F8A4C; --ok-soft:#DDF1E5; --warn:#9A5B00; --warn-soft:#FBEBCF; --crit:#C23A2C; --crit-soft:#F8DEDA;
  --focus:#2A78D6;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){ color-scheme:dark;
    --ground:#0F1216; --surface:#181C22; --sunk:#222730; --line:#2D333D;
    --ink:#EEF1F5; --ink-2:#B4BCC8; --ink-3:#848D9A;
    --s1:#3987E5; --s2:#D95926; --s3:#199E70; --idle:#39404B;
    --ok:#46B874; --ok-soft:#173424; --warn:#E3A43E; --warn-soft:#3A2B12; --crit:#EF6B5E; --crit-soft:#3E1C19;
    --focus:#6DA7EC; }
}
:root[data-theme="dark"]{ color-scheme:dark;
  --ground:#0F1216; --surface:#181C22; --sunk:#222730; --line:#2D333D;
  --ink:#EEF1F5; --ink-2:#B4BCC8; --ink-3:#848D9A;
  --s1:#3987E5; --s2:#D95926; --s3:#199E70; --idle:#39404B;
  --ok:#46B874; --ok-soft:#173424; --warn:#E3A43E; --warn-soft:#3A2B12; --crit:#EF6B5E; --crit-soft:#3E1C19;
  --focus:#6DA7EC; }
body{background:var(--ground);color:var(--ink);font:15px/1.5 "Instrument Sans",-apple-system,"Segoe UI",sans-serif}
.wrap{max-width:1040px;margin:0 auto;padding-inline:16px;padding-block:28px 48px;display:grid;gap:22px}
.mono,code,.cmd,.kick,.hb-v,.t-k{font-family:"JetBrains Mono",ui-monospace,Menlo,monospace}
.ic{width:22px;height:22px;flex:none;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
.ic.sm{width:14px;height:14px}
header{display:grid;gap:4px}
.kick{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--ink-3);margin:0}
h1{font-size:clamp(26px,4vw,36px);line-height:1.1;margin:0;font-weight:700;text-wrap:balance}
h2{font-size:18px;margin:0;display:flex;gap:10px;align-items:center;font-weight:600}
h2 .ic{color:var(--s1)}
header p{margin:0;color:var(--ink-2)}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:12px}
.tile{background:var(--surface);color:var(--ink);border:1px solid var(--line);border-radius:10px;padding:14px;display:grid;grid-template-columns:auto 1fr;gap:4px 12px;align-items:start;border-top:3px solid var(--line)}
.tile.warn{border-top-color:var(--warn)} .tile.crit{border-top-color:var(--crit)} .tile.ok{border-top-color:var(--ok)}
.tile>.ic{color:var(--ink-2);margin-top:2px}
.tile p{margin:0}
.t-k{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--ink-3)}
.t-v{font-size:30px;font-weight:700;font-variant-numeric:tabular-nums;line-height:1.15}
.t-s{color:var(--ink-2);font-size:13px}
.tile .chip{grid-column:2;justify-self:start}
.chip{display:inline-flex;gap:5px;align-items:center;font-size:12px;font-weight:600;padding:2px 8px;border-radius:999px;background:var(--sunk);color:var(--ink-2)}
.chip.ok{background:var(--ok-soft);color:var(--ok)} .chip.warn{background:var(--warn-soft);color:var(--warn)} .chip.crit{background:var(--crit-soft);color:var(--crit)}
.panel{background:var(--surface);color:var(--ink);border:1px solid var(--line);border-radius:12px;padding:18px;display:grid;gap:14px;min-width:0}
.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr));gap:22px}
.sub{font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:var(--ink-3);margin:6px 0 -6px;font-family:"JetBrains Mono",monospace}
.stack{display:flex;gap:2px;height:22px;border-radius:5px;overflow:hidden;background:var(--surface)}
.seg{min-width:2px}
.legend{list-style:none;margin:0;padding:0;display:flex;flex-wrap:wrap;gap:6px 16px;font-size:13px;color:var(--ink-2)}
.legend i{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:6px;vertical-align:-1px}
.legend b{color:var(--ink);font-variant-numeric:tabular-nums;font-weight:600} .legend span{color:var(--ink-3)}
.hbars{display:grid;gap:7px}
.hb{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(0,2fr) auto;gap:10px;align-items:center;font-size:13px}
.hb-l{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--ink-2);display:flex;gap:6px;align-items:center;min-width:0}
.hb-t{position:relative;height:12px;background:var(--sunk);border-radius:0 4px 4px 0;display:flex;gap:2px}
.hb-b{display:block;height:100%;background:var(--s1);border-radius:0 4px 4px 0}
.hb-b.rec{background:var(--s2)}
.hb.flagged .hb-b{background:var(--crit)}
.hb-ref{position:absolute;top:-3px;bottom:-3px;width:0;border-left:2px dashed var(--ink-3)}
.hb-v{font-size:12px;font-variant-numeric:tabular-nums;color:var(--ink);text-align:right;min-width:62px}
.hb-v .n{color:var(--ink-3)}
.flag{display:inline-flex;gap:3px;align-items:center;font-size:11px;color:var(--crit);font-weight:600;flex:none}
.axisnote{margin:0;font-size:12px;color:var(--ink-3);display:flex;gap:8px;align-items:center}
.refkey{display:inline-block;width:0;height:12px;border-left:2px dashed var(--ink-3)}
.meter{display:grid;gap:6px}
.meter-h{display:flex;flex-wrap:wrap;gap:6px 12px;align-items:center;font-size:14px}
.meter-h b{font-variant-numeric:tabular-nums}
.meter-t{height:12px;background:var(--sunk);border-radius:6px;overflow:hidden}
.meter-b{display:block;height:100%;background:var(--ok)}
.meter-b.warn{background:var(--warn)} .meter-b.crit{background:var(--crit)}
.kv{margin:0;color:var(--ink-2);font-size:14px} .kv b{color:var(--ink);font-variant-numeric:tabular-nums}
.empty{margin:0;color:var(--ink-3);font-size:14px}
.scroll{overflow-x:auto}
.chart{width:100%;min-width:480px;height:auto;display:block}
.chart .grid{stroke:var(--line);stroke-width:1}
.chart .tick{fill:var(--ink-3);font:11px "JetBrains Mono",monospace}
.chart .dl{fill:var(--ink);font:600 12px "Instrument Sans",sans-serif}
.plain{margin:0;padding-left:18px;color:var(--ink-2);font-size:13px}
/* decisions */
.decide{border-color:var(--s1);border-width:1.5px}
.decide-h{display:flex;flex-wrap:wrap;gap:10px 16px;align-items:center;justify-content:space-between}
.decide-h p{margin:4px 0 0;color:var(--ink-2);font-size:14px;max-width:62ch}
.acts{list-style:none;margin:0;padding:0;display:grid;gap:10px}
.act{display:grid;grid-template-columns:auto 1fr;gap:4px 12px;padding:12px;border:1px solid var(--line);border-radius:9px;background:var(--surface)}
.act.is-selected{border-color:var(--s1);background:color-mix(in srgb,var(--s1) 7%,var(--surface))}
.act.is-applied{border-color:var(--ok)} .act.is-failed{border-color:var(--crit)}
.act input{width:20px;height:20px;margin:2px 0 0;accent-color:var(--s1)}
.act input:focus-visible{outline:2px solid var(--focus);outline-offset:2px}
.act label{font-weight:600;cursor:pointer}
.act .why{grid-column:2;color:var(--ink-2);font-size:13px;margin:0}
.cmd{grid-column:2;margin:0;font-size:12.5px;background:var(--sunk);color:var(--ink);padding:7px 9px;border-radius:6px;overflow-x:auto;white-space:pre}
.act .meta{grid-column:2;display:flex;flex-wrap:wrap;gap:6px;align-items:center}
.act .out{grid-column:2;margin:0;font-size:12.5px;color:var(--ink-2);white-space:pre-wrap;font-family:"JetBrains Mono",monospace;border-left:2px solid var(--line);padding-left:8px}
.chip.sel{background:color-mix(in srgb,var(--s1) 16%,var(--surface));color:var(--s1)}
.chip.sudo{background:var(--warn-soft);color:var(--warn)}
.bar{display:flex;flex-wrap:wrap;gap:10px;align-items:center}
button{font:600 14px "Instrument Sans",sans-serif;border-radius:8px;padding:9px 14px;border:1px solid var(--s1);background:var(--s1);color:#fff;display:inline-flex;gap:7px;align-items:center;cursor:pointer}
button.ghost{background:var(--surface);color:var(--s1)}
button:disabled{opacity:.45;cursor:not-allowed}
button:focus-visible{outline:2px solid var(--focus);outline-offset:2px}
.notice{margin:0;padding:10px 12px;border-radius:8px;background:var(--sunk);color:var(--ink);font-size:14px}
.notice code{background:var(--surface);padding:1px 6px;border-radius:4px}
.flist{list-style:none;margin:0;padding:0;display:grid;gap:8px}
.flist li{display:grid;grid-template-columns:auto 1fr;gap:10px;font-size:14px;align-items:start}
.flist li.finding .ic{color:var(--crit)} .flist li.info .ic{color:var(--ink-3)}
details summary{cursor:pointer;color:var(--ink-2);font-size:14px}
details pre{font-size:12px;overflow-x:auto;background:var(--sunk);color:var(--ink);padding:12px;border-radius:8px;max-height:420px}
footer{font:12px "JetBrains Mono",monospace;color:var(--ink-3)}
@media (prefers-reduced-motion:no-preference){.act{transition:border-color .15s,background .15s}}
</style>
<div class="wrap">
<header>
  <p class="kick">mac-doctor · {{HOST}}</p>
  <h1>Pulso de {{HOST}}</h1>
  <p>Ejecución del doctor: <span class="mono">{{RAN_AT}}</span> · CPU y RAM medidas al generar esta página: <span class="mono">{{NOW}}</span></p>
</header>

<section class="tiles" aria-label="Resumen">{{TILES}}</section>

<section class="panel decide" id="decisiones">
  <div class="decide-h">
    <div>
      <h2>{{I_TERM}}Decisiones</h2>
      <p>Marca lo que quieres que el agente aplique. Tus marcas se guardan al momento; el agente las lee, revisa que sigan siendo válidas, las aplica y deja aquí el resultado de cada una.</p>
    </div>
    <div class="bar">
      <button id="send" type="button" disabled>{{I_SEND}}<span id="send-l">Enviar al agente</span></button>
    </div>
  </div>
  <p class="notice" id="status" hidden></p>
  <ul class="acts" id="acts"></ul>
</section>

<div class="grid2">
  <section class="panel"><h2>{{I_CPU}}CPU</h2>
    {{CPU_STACK}}{{LOAD}}
    <p class="sub">Procesos que más CPU usan</p>{{CPU_BARS}}
  </section>
  <section class="panel"><h2>{{I_RAM}}Memoria</h2>
    {{RAM_STACK}}{{SWAP}}
    <p class="sub">RAM por aplicación (suma de procesos)</p>{{RAM_BARS}}
  </section>
  <section class="panel"><h2>{{I_DISK}}Disco</h2>{{DISK}}{{COLIMA}}</section>
  <section class="panel"><h2>{{I_BOX}}Docker por dentro</h2>{{DOCKER}}</section>
</div>

<section class="panel"><h2>{{I_TREND}}Tendencia del disco</h2>{{TREND}}{{TREND_LINES}}</section>

<section class="panel"><h2>{{I_ALERT}}Hallazgos ({{NFIND}}) y notas</h2>
  <ul class="flist">{{FINDINGS}}{{INFO}}</ul>
  <details><summary>Salida completa del doctor</summary><pre>{{RAW}}</pre></details>
</section>

<footer>~/.claude/skills/mac-doctor · {{NACT}} acciones propuestas · generado {{NOW}}</footer>
</div>

<script id="run" type="application/json">{{PAYLOAD}}</script>
<script>
(() => {
  const RUN = JSON.parse(document.getElementById("run").textContent);
  const list = document.getElementById("acts");
  const statusEl = document.getElementById("status");
  const sendBtn = document.getElementById("send");
  const sendL = document.getElementById("send-l");
  const PHRASE = "aplica las decisiones del artifact de mac-doctor";
  let db = null, states = {}, request = null, busy = new Set(), readOnly = true;

  const LABEL = {selected: "Marcada", sent: "Enviada", running: "Aplicando…", applied: "Aplicada", failed: "Falló", skipped: "Omitida"};
  const CHIP = {selected: "sel", sent: "sel", running: "warn", applied: "ok", failed: "crit", skipped: ""};
  const done = s => ["running", "applied", "failed", "skipped"].includes(s);

  function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }

  function render() {
    list.replaceChildren();
    if (!RUN.actions.length) { list.append(el("li", "empty", "Esta ejecución no propuso ninguna acción.")); }
    for (const a of RUN.actions) {
      const st = states[a.id] || {};
      const s = st.state || "pending";
      const li = el("li", "act is-" + s);
      const box = el("input"); box.type = "checkbox"; box.id = "act-" + a.id;
      box.checked = s !== "pending" && s !== "skipped";
      box.disabled = readOnly || !a.selectable || done(s) || busy.has(a.id);
      box.addEventListener("change", () => toggle(a, box.checked));
      const lab = el("label", null, a.title); lab.htmlFor = box.id;
      li.append(box, lab);
      if (a.finding && a.finding !== a.title) li.append(el("p", "why", a.finding));
      if (a.command) li.append(el("pre", "cmd", a.command));
      const meta = el("div", "meta");
      if (s !== "pending") meta.append(el("span", "chip " + (CHIP[s] || ""), LABEL[s] || s));
      if (a.sudo) meta.append(el("span", "chip sudo", "Requiere sudo: lo ejecutas tú"));
      if (!a.selectable) meta.append(el("span", "chip", "Necesita datos a mano: no se puede marcar"));
      if (a.note) meta.append(el("span", "why", a.note));
      if (meta.childNodes.length) li.append(meta);
      if (st.result) li.append(el("p", "out", st.result));
      list.append(li);
    }
    const picked = RUN.actions.filter(a => (states[a.id] || {}).state === "selected").length;
    sendBtn.disabled = readOnly || picked === 0;
    sendL.textContent = picked ? `Enviar al agente (${picked})` : "Enviar al agente";
  }

  function say(msg, withPhrase) {
    statusEl.hidden = false; statusEl.replaceChildren(el("span", null, msg));
    if (withPhrase) {
      const c = el("code", null, PHRASE); const b = el("button", "ghost", "Copiar frase"); b.type = "button";
      b.style.marginLeft = "8px"; b.style.padding = "3px 10px";
      b.addEventListener("click", async () => {
        try { await navigator.clipboard.writeText(PHRASE); b.textContent = "Copiada"; }
        catch { const r = document.createRange(); r.selectNodeContents(c); const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
      });
      statusEl.append(" ", c, b);
    }
  }

  async function toggle(a, on) {
    busy.add(a.id); render();
    try {
      await db.doc("actions/" + a.id).set({
        runId: RUN.runId, title: a.title, command: a.command, finding: a.finding, sudo: a.sudo,
        state: on ? "selected" : "pending", updatedAt: new Date().toISOString(), by: "viewer",
      });
    } catch (e) {
      say(e && e.code === "invalid_argument" ? "No tienes permiso para guardar decisiones en esta página." : "No se pudo guardar la marca. Inténtalo de nuevo.");
      if (e && e.code === "invalid_argument") readOnly = true;
    } finally { busy.delete(a.id); render(); }
  }

  sendBtn.addEventListener("click", async () => {
    const ids = RUN.actions.filter(a => (states[a.id] || {}).state === "selected").map(a => a.id);
    sendBtn.disabled = true;
    try {
      await db.doc("control/request").set({runId: RUN.runId, ids, requestedAt: new Date().toISOString(), status: "requested"});
      say(`Enviadas ${ids.length} decisiones. Dile al agente en la terminal:`, true);
    } catch { say("No se pudo enviar. Inténtalo de nuevo."); }
    render();
  });

  function showRequest() {
    if (!request || request.runId !== RUN.runId) return;
    if (request.status === "working") say("El agente está aplicando tus decisiones…");
    else if (request.status === "done") say(request.summary || "El agente terminó. El resultado de cada acción está debajo.");
    else say(`Enviadas ${(request.ids || []).length} decisiones. Dile al agente en la terminal:`, true);
  }

  render();
  (async () => {
    db = window.claude && window.claude.use ? await window.claude.use("db") : null;
    if (!db) { say("Vista de solo lectura: este visor no puede guardar decisiones. Pídeselas al agente en la terminal."); return; }
    readOnly = false; render();
    db.collection("actions").where("runId", "==", RUN.runId).onSnapshot(snap => {
      states = {}; for (const d of snap.docs) states[d.id] = d.data(); render();
    }, () => { readOnly = true; render(); say("Se perdió la conexión con los datos de la página. Recarga para volver a marcar."); });
    db.doc("control/request").onSnapshot(snap => { request = snap.exists ? snap.data() : null; showRequest(); }, () => {});
  })();
})();
</script>
"""

if __name__ == "__main__":
    main()
