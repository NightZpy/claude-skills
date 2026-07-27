#!/usr/bin/env python3
"""Mechanical update CLI for q3-data.json + rebuild via build_q3.py.

Subcommands: touch, done, journal, issue-state, add-issue, note, memory-add,
build, status, validate, sync-linear, recover.
Every mutating subcommand backs up q3-data.json, loads it, validates,
mutates, writes back (json.dump ensure_ascii=False indent=1), bumps
meta.updated, then rebuilds by running `python3 build_q3.py` with
cwd=--dir. `validate`, `build`, `status`, `recover`, and dry-runs never
back up.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

DATA_FILE = "q3-data.json"
PROMPT_FILE = "q3-prompt.txt"
BUILD_SCRIPT = "build_q3.py"
BACKUPS_DIR = ".backups"
MAX_BACKUPS = 20
ISSUE_LABEL_RE = re.compile(r"^([A-Z]+)-(\d+)$")

# Mirrors the (JS_NAME, data_key) pairs build_q3.py writes as `const JS_NAME=...;`
# lines into the /*@DATA*/ block.
RECOVER_CONSTS = [
    ("RITUALS", "rituals"),
    ("NODES", "nodes"),
    ("EDGES", "edges"),
    ("LENSES", "lenses"),
    ("DEADLINES", "deadlines"),
    ("WEEK_PENDINGS", "week_pendings"),
    ("FOCUS", "focus"),
    ("DONE_LOG", "done_log"),
    ("JOURNAL", "journal"),
]

# Stable anchors in _q3-shell.tpl surrounding each injected tab's inner HTML:
# (prefix immediately before the content, suffix immediately after it).
RECOVER_TAB_ANCHORS = {
    "ritmo": ('<div class="ptab" id="tab-ritmo">', "\n      </div>"),
    "proyectos": ('<div class="ptab" id="tab-proyectos">', "\n      </div>"),
    "aliados": ('<div class="ptab" id="tab-aliados">', "\n      </div>"),
    "insights": ('<div class="ptab" id="tab-ins">', "\n      </div>"),
    "kpis": ('<div class="ptab" id="tab-kpi">', "\n      </div>"),
    "fuentes": ('<div class="ptab" id="tab-src">', "\n      </div>"),
    "prompt_head": ('<div class="ptab" id="tab-prompt">', '<pre id="promptText"'),
}

RECOVER_TPL_ANCHORS = {
    "tpl-daily": '<pre id="tpl-daily" style="display:none">',
    "tpl-weekly": '<pre id="tpl-weekly" style="display:none">',
    "tpl-health": '<pre id="tpl-health" style="display:none">',
}

# Seeded on first memory-add if data["memory"] doesn't exist yet: (id, icon, label).
MEMORY_SEED_CATS = [
    ("personas", "\U0001F465", "Personas"),
    ("lecciones", "\U0001F393", "Lecciones"),
    ("decisiones", "⚖️", "Decisiones"),
    ("gotchas", "⚠️", "Gotchas"),
    ("preferencias", "\U0001F39B️", "Preferencias"),
]
MEMORY_NOTE_ID_RE = re.compile(r"^m-(\d+)$")


def die(msg):
    print("error: %s" % msg, file=sys.stderr)
    sys.exit(1)


def valid_date(s):
    try:
        datetime.date.fromisoformat(s)
    except ValueError:
        die("invalid date (expected YYYY-MM-DD): %r" % s)
    return s


def today():
    return datetime.date.today().isoformat()


def load_data(base_dir):
    path = os.path.join(base_dir, DATA_FILE)
    if not os.path.isfile(path):
        die("%s not found in %s" % (DATA_FILE, base_dir))
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        die("%s is not valid JSON: %s" % (DATA_FILE, e))


def backup_data(base_dir):
    src = os.path.join(base_dir, DATA_FILE)
    if not os.path.isfile(src):
        return None
    backups_dir = os.path.join(base_dir, BACKUPS_DIR)
    os.makedirs(backups_dir, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = os.path.join(backups_dir, "q3-data.%s.json" % ts)
    shutil.copy2(src, dest)
    existing = sorted(
        f
        for f in os.listdir(backups_dir)
        if f.startswith("q3-data.") and f.endswith(".json")
    )
    for old in existing[:-MAX_BACKUPS]:
        os.remove(os.path.join(backups_dir, old))
    return dest


def save_data(base_dir, data, anchor_date=None):
    """anchor_date: ONLY cmd_touch may pass it. Backdated entries (done/journal --date)
    must NEVER rewind meta.updated — the anchor is always the real today."""
    backup_path = backup_data(base_dir)
    data["meta"]["updated"] = anchor_date or today()
    path = os.path.join(base_dir, DATA_FILE)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    return backup_path


def run_build(base_dir):
    result = subprocess.run(
        [sys.executable, BUILD_SCRIPT],
        cwd=base_dir,
        capture_output=True,
        text=True,
    )
    print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        die("build_q3.py failed (exit %d)" % result.returncode)
    git_sync(base_dir)


def git_sync(base_dir):
    """Best-effort: commit+push any change so the private repo stays the versioned backup."""
    if not os.path.isdir(os.path.join(base_dir, ".git")):
        return
    def _git(*args, timeout=30):
        return subprocess.run(["git"] + list(args), cwd=base_dir,
                              capture_output=True, text=True, timeout=timeout)
    try:
        if not _git("status", "--porcelain").stdout.strip():
            return
        _git("add", "-A")
        msg = "auto: " + " ".join(sys.argv[1:])[:100] if len(sys.argv) > 1 else "auto: update"
        c = _git("commit", "-m", msg)
        if c.returncode != 0:
            print("git-sync: commit failed: %s" % c.stderr.strip()[:200], file=sys.stderr)
            return
        p = _git("push", timeout=60)
        print("git-sync: committed%s" % ("" if p.returncode == 0 else " (push failed — will push next time)"))
    except Exception as e:  # offline, timeout, etc. — never break the command
        print("git-sync: skipped (%s)" % e, file=sys.stderr)


def is_satellite(node):
    return node.get("group") == "issues" and "kind" in node


def find_node(data, node_id):
    for n in data["nodes"]:
        if n.get("id") == node_id:
            return n
    return None


def close_matches(data, node_id, limit=5):
    ids = [n.get("id", "") for n in data["nodes"]]
    needle = node_id.lower()
    scored = sorted(ids, key=lambda i: (needle not in i.lower(), i))
    return scored[:limit]


def find_memory_cat(data, cat_id):
    for cat in data.get("memory", {}).get("cats", []):
        if cat.get("id") == cat_id:
            return cat
    return None


def all_memory_notes(data):
    notes = []
    for cat in data.get("memory", {}).get("cats", []):
        notes.extend(cat.get("notes", []) or [])
    return notes


def next_memory_note_id(data):
    max_n = 0
    for n in all_memory_notes(data):
        m = MEMORY_NOTE_ID_RE.match(n.get("id", ""))
        if m:
            max_n = max(max_n, int(m.group(1)))
    return "m-%d" % (max_n + 1)


# ---------------------------------------------------------------- touch ----
def cmd_touch(args, base_dir):
    data = load_data(base_dir)
    date = valid_date(args.date) if args.date else today()
    backup_path = save_data(base_dir, data, date)
    print("touched meta.updated -> %s" % date)
    print("backup: %s" % backup_path)
    run_build(base_dir)


# ----------------------------------------------------------------- done ----
def cmd_done(args, base_dir):
    data = load_data(base_dir)
    date = valid_date(args.date) if args.date else today()
    icon = args.icon or "\U0001F4C4"  # 📄
    entry = {"date": date, "i": icon, "t": args.label, "u": args.url}
    if args.guide:
        entry["g"] = args.guide
    if getattr(args, "nav", None):
        nav = args.nav
        if not nav.startswith("r-") and find_node(data, nav) is None:
            die("nav target %r not found (must be a node id or ritual id r-*). close matches: %s"
                % (nav, close_matches(data, nav)))
        entry["nav"] = nav

    log = data.setdefault("done_log", [])
    dup = any(e.get("u") == args.url and e.get("date") == date for e in log)
    if dup:
        print("already logged (same url + date): %s" % args.url)
    else:
        log.append(entry)
        log.sort(key=lambda e: e.get("date", ""), reverse=True)
        print("logged: %s — %s" % (date, args.label))

    backup_path = save_data(base_dir, data)
    print("backup: %s" % backup_path)
    run_build(base_dir)


# --------------------------------------------------------------- journal ---
def cmd_journal(args, base_dir):
    data = load_data(base_dir)
    node = find_node(data, args.node)
    if node is None:
        matches = close_matches(data, args.node)
        die(
            "node id %r not found in nodes. close matches: %s"
            % (args.node, ", ".join(matches))
        )
    date = valid_date(args.date) if args.date else today()
    icon = args.icon or "\U0001F4DD"  # 📝
    entry = {"date": date, "node": args.node, "i": icon, "t": args.text}

    journal = data.setdefault("journal", [])
    journal.append(entry)
    journal.sort(key=lambda e: e.get("date", ""), reverse=True)
    print("journal entry added for %s on %s" % (args.node, date))

    backup_path = save_data(base_dir, data)
    print("backup: %s" % backup_path)
    run_build(base_dir)


# ----------------------------------------------------------- pending-done --
def cmd_pending_done(args, base_dir):
    data = load_data(base_dir)
    pendings = data.get("week_pendings", [])
    hits = [w for w in pendings if w and w[0] == args.key]
    if not hits:
        keys = ", ".join(w[0] for w in pendings if w)
        die("pending key %r not found. existing keys: %s" % (args.key, keys))
    w = hits[0]
    pendings.remove(w)
    print("retired pending %r: %s %s" % (w[0], w[1], w[2]))

    if args.node:
        node = find_node(data, args.node)
        if node is None:
            die("node id %r not found. close matches: %s"
                % (args.node, close_matches(data, args.node)))
        text = args.note or ("Pendiente cerrado: %s" % w[2])
        journal = data.setdefault("journal", [])
        journal.append({"date": today(), "node": args.node, "i": "✅", "t": text})
        journal.sort(key=lambda e: e.get("date", ""), reverse=True)
        print("journal entry added for %s" % args.node)

    backup_path = save_data(base_dir, data)
    print("backup: %s" % backup_path)
    run_build(base_dir)


# ------------------------------------------------------------ issue-state --
def cmd_issue_state(args, base_dir):
    data = load_data(base_dir)
    node_id = args.id
    node = find_node(data, node_id)
    if node is None and not node_id.startswith("iss-"):
        node = find_node(data, "iss-" + node_id)
        if node is not None:
            node_id = "iss-" + node_id
    if node is None:
        matches = close_matches(data, args.id)
        die(
            "issue id %r not found (tried %r and 'iss-'+id). close matches: %s"
            % (args.id, args.id, ", ".join(matches))
        )
    if node.get("kind") not in ("issue", "topic"):
        die("node %r is not kind issue|topic (kind=%r)" % (node_id, node.get("kind")))

    node["state"] = args.state
    print("%s -> state=%s" % (node_id, args.state))
    backup_path = save_data(base_dir, data)
    print("backup: %s" % backup_path)
    run_build(base_dir)


# --------------------------------------------------------------- add-issue -
def cmd_add_issue(args, base_dir):
    data = load_data(base_dir)
    new_id = "iss-" + args.id

    if find_node(data, new_id) is not None:
        die("node %r already exists" % new_id)

    parent = find_node(data, args.parent)
    if parent is None:
        matches = close_matches(data, args.parent)
        die(
            "parent %r not found. close matches: %s"
            % (args.parent, ", ".join(matches))
        )
    if is_satellite(parent):
        die("parent %r is itself a satellite node, not a theme" % args.parent)

    node = {
        "id": new_id,
        "kind": "issue",
        "group": "issues",
        "parent": args.parent,
        "owner": args.owner or "other",
        "state": args.state or "live",
        "icon": args.icon or "\U0001F4CB",  # 📋
        "label": args.id,
        "sub": args.sub,
        "url": "https://tracker.example.com/issue/" + args.id,
    }
    data["nodes"].append(node)
    print("added %s under %s" % (new_id, args.parent))
    backup_path = save_data(base_dir, data)
    print("backup: %s" % backup_path)
    run_build(base_dir)


# ------------------------------------------------------------------ note ---
def cmd_note(args, base_dir):
    data = load_data(base_dir)
    date = valid_date(args.date) if args.date else today()

    inbox = data.setdefault("inbox", [])
    inbox.insert(0, {"date": date, "t": args.text})
    print("inbox: %d items" % len(inbox))

    backup_path = save_data(base_dir, data)
    print("backup: %s" % backup_path)
    run_build(base_dir)


# ------------------------------------------------------------- memory-add --
def cmd_memory_add(args, base_dir):
    data = load_data(base_dir)
    memory = data.setdefault("memory", {})
    if not memory.get("cats"):
        memory["cats"] = [
            {"id": cid, "icon": icon, "label": label, "notes": []}
            for cid, icon, label in MEMORY_SEED_CATS
        ]

    cat = find_memory_cat(data, args.cat)
    if cat is None:
        valid_ids = [c.get("id") for c in memory.get("cats", [])]
        die("unknown memory category %r. valid ids: %s" % (args.cat, ", ".join(valid_ids)))

    refs = [r for r in (args.refs.split(",") if args.refs else []) if r]
    for ref in refs:
        if find_node(data, ref) is None:
            matches = close_matches(data, ref)
            die("ref %r not found in nodes. close matches: %s" % (ref, ", ".join(matches)))

    date = valid_date(args.date) if args.date else today()
    new_id = next_memory_note_id(data)
    note = {
        "id": new_id,
        "date": date,
        "date_upd": date,
        "t": args.text,
        "refs": refs,
        "pinned": bool(args.pin),
    }
    cat.setdefault("notes", []).append(note)
    print(new_id)

    backup_path = save_data(base_dir, data)
    print("backup: %s" % backup_path)
    run_build(base_dir)


# ----------------------------------------------------------------- build ---
def cmd_build(args, base_dir):
    run_build(base_dir)


# ---------------------------------------------------------------- status ---
def cmd_status(args, base_dir):
    data = load_data(base_dir)
    nodes = data.get("nodes", [])
    themes = [n for n in nodes if not is_satellite(n)]
    sats = [n for n in nodes if is_satellite(n)]
    sat_live = sum(1 for n in sats if n.get("state") == "live")
    sat_done = sum(1 for n in sats if n.get("state") == "done")

    done_log = data.get("done_log", [])
    journal = data.get("journal", [])

    print("meta.updated: %s" % data.get("meta", {}).get("updated"))
    print("nodes: %d total (%d themes, %d satellites)" % (len(nodes), len(themes), len(sats)))
    print("  satellites: %d live, %d done" % (sat_live, sat_done))
    print("done_log: %d entries" % len(done_log))
    if done_log:
        latest = max(done_log, key=lambda e: e.get("date", ""))
        print("  latest: %s — %s" % (latest.get("date"), latest.get("t")))
    print("journal: %d entries" % len(journal))

    print("inbox: %d pending" % len(data.get("inbox", [])))
    mem_cats = data.get("memory", {}).get("cats", [])
    mem_notes = all_memory_notes(data)
    mem_pinned = sum(1 for n in mem_notes if n.get("pinned"))
    print("memory: %d notes in %d cats (%d pinned)" % (len(mem_notes), len(mem_cats), mem_pinned))

    updated = data.get("meta", {}).get("updated", today())
    deadlines = data.get("deadlines", [])
    upcoming = sorted(
        [d for d in deadlines if d and d[0] >= updated], key=lambda d: d[0]
    )
    print("next deadlines (relative to %s):" % updated)
    if not upcoming:
        print("  (none)")
    for d in upcoming[:3]:
        date, label = d[0], d[1]
        print("  %s — %s" % (date, label))


# --------------------------------------------------------------- validate --
REQUIRED_TOP_KEYS = [
    "nodes", "edges", "lenses", "rituals", "deadlines", "week_pendings",
    "focus", "evidence", "templates", "narrativa", "meta", "tabs", "done_log",
]


def cmd_validate(args, base_dir):
    data = load_data(base_dir)
    errors = []

    for key in REQUIRED_TOP_KEYS:
        if key not in data:
            errors.append("missing top-level key: %s" % key)

    nodes = data.get("nodes", [])
    seen = set()
    for n in nodes:
        nid = n.get("id")
        if not nid:
            errors.append("node missing id: %r" % n)
            continue
        if nid in seen:
            errors.append("duplicate node id: %s" % nid)
        seen.add(nid)
        if not n.get("group"):
            errors.append("node %s missing group" % nid)

    theme_ids = {n.get("id") for n in nodes if "kind" not in n}
    all_ids = {n.get("id") for n in nodes}

    for n in nodes:
        if "kind" not in n:
            continue
        nid = n.get("id", "<missing id>")
        parent = n.get("parent")
        if not parent:
            errors.append("satellite %s missing parent" % nid)
        elif parent not in theme_ids:
            if parent in all_ids:
                errors.append(
                    "satellite %s parent %r is a satellite, not a theme node" % (nid, parent)
                )
            else:
                errors.append("satellite %s parent %r not found" % (nid, parent))
        if n.get("owner") not in ("mine", "other"):
            errors.append("satellite %s invalid owner: %r" % (nid, n.get("owner")))
        if n.get("state") not in ("live", "done"):
            errors.append("satellite %s invalid state: %r" % (nid, n.get("state")))

    for e in data.get("edges", []):
        for side in ("from", "to"):
            if e.get(side) not in all_ids:
                errors.append("edge %r has %s referencing missing node %r" % (e, side, e.get(side)))

    def check_date(s, ctx):
        try:
            datetime.date.fromisoformat(s)
        except (ValueError, TypeError):
            errors.append("%s: invalid date %r" % (ctx, s))

    for d in data.get("deadlines", []):
        if not d:
            errors.append("malformed deadline entry: %r" % (d,))
            continue
        check_date(d[0], "deadline")

    for e in data.get("done_log", []):
        check_date(e.get("date"), "done_log entry")
        if not e.get("t"):
            errors.append("done_log entry missing t: %r" % e)
        if not e.get("u"):
            errors.append("done_log entry missing u: %r" % e)

    for e in data.get("journal") or []:
        check_date(e.get("date"), "journal entry")
        if e.get("node") not in all_ids:
            errors.append("journal entry references missing node %r" % e.get("node"))

    check_date(data.get("meta", {}).get("updated"), "meta.updated")

    for e in data.get("inbox") or []:
        check_date(e.get("date"), "inbox entry")
        if not e.get("t"):
            errors.append("inbox entry missing t: %r" % e)

    mem_cat_ids = set()
    mem_note_ids = set()
    for cat in data.get("memory", {}).get("cats", []) or []:
        cid = cat.get("id")
        if not cid:
            errors.append("memory cat missing id: %r" % cat)
        elif cid in mem_cat_ids:
            errors.append("duplicate memory cat id: %s" % cid)
        else:
            mem_cat_ids.add(cid)
        for n in cat.get("notes", []) or []:
            nid = n.get("id")
            if not nid:
                errors.append("memory note missing id: %r" % n)
            elif nid in mem_note_ids:
                errors.append("duplicate memory note id: %s" % nid)
            else:
                mem_note_ids.add(nid)
            check_date(n.get("date"), "memory note %s" % nid)
            check_date(n.get("date_upd"), "memory note %s date_upd" % nid)
            for ref in n.get("refs", []) or []:
                if ref not in all_ids:
                    errors.append("memory note %s references missing node %r" % (nid, ref))

    for lens in data.get("lenses", []):
        lnodes = lens.get("nodes")
        if lnodes != "*":
            for nid in lnodes or []:
                if nid not in all_ids:
                    errors.append("lens %r references missing node %r" % (lens.get("id"), nid))

    for rit in data.get("rituals", []):
        for nid in rit.get("nodes", []) or []:
            if nid not in all_ids:
                errors.append("ritual %r references missing node %r" % (rit.get("id"), nid))

    if errors:
        print("FAIL: %d problem(s)" % len(errors))
        for e in errors:
            print("  - %s" % e)
        sys.exit(1)

    print(
        "OK: %d nodes, %d edges, %d done_log, %d journal, meta.updated=%s"
        % (
            len(nodes),
            len(data.get("edges", [])),
            len(data.get("done_log", [])),
            len(data.get("journal") or []),
            data.get("meta", {}).get("updated"),
        )
    )


# ------------------------------------------------------------- sync-linear -
def linear_api_key():
    key = os.environ.get("LINEAR_API_KEY")
    if key:
        return key.strip()
    path = os.path.expanduser("~/.linear_api_key")
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            key = f.read().strip()
        return key or None
    return None


def fetch_linear_states(api_key, team, numbers):
    query = (
        'query{ issues(filter:{team:{key:{eq:"%s"}}, number:{in:[%s]}}, first: 100){ '
        "nodes{ identifier state{ name type } updatedAt } } }"
        % (team, ",".join(str(n) for n in numbers))
    )
    body = json.dumps({"query": query}).encode("utf-8")
    req = urllib.request.Request(
        "https://api.linear.app/graphql",
        data=body,
        headers={"Authorization": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    if "errors" in payload:
        raise RuntimeError(str(payload["errors"]))
    return {node["identifier"]: node["state"] for node in payload["data"]["issues"]["nodes"]}


def map_linear_state(state):
    return "done" if state.get("type") in ("completed", "canceled") else "live"


def cmd_sync_linear(args, base_dir):
    data = load_data(base_dir)
    sats = [
        n
        for n in data.get("nodes", [])
        if n.get("kind") == "issue" and ISSUE_LABEL_RE.match(n.get("label", ""))
    ]

    mock = None
    if args.mock_file:
        with open(args.mock_file, "r", encoding="utf-8") as f:
            mock = json.load(f)
    else:
        api_key = linear_api_key()
        if not api_key:
            die(
                "no Linear API key found. Set the LINEAR_API_KEY env var, or create "
                "~/.linear_api_key containing a Personal API key (Linear -> Settings -> "
                "Security & access -> Personal API keys). Alternatively pass "
                "--mock-file for an offline/test run."
            )

    states = {}
    if mock is not None:
        states = mock
    else:
        by_team = {}
        for n in sats:
            team = ISSUE_LABEL_RE.match(n["label"]).group(1)
            by_team.setdefault(team, []).append(n)
        for team, team_nodes in by_team.items():
            numbers = [int(ISSUE_LABEL_RE.match(n["label"]).group(2)) for n in team_nodes]
            try:
                states.update(fetch_linear_states(api_key, team, numbers))
            except Exception as e:
                die("Linear API request failed for team %s: %s" % (team, e))

    updated, unchanged, not_found = [], 0, []
    for n in sats:
        st = states.get(n["label"])
        if st is None:
            not_found.append(n["label"])
            continue
        new_state = map_linear_state(st)
        if new_state != n.get("state"):
            updated.append((n, new_state, st))
        else:
            unchanged += 1

    for label in not_found:
        print("warning: %s not returned by Linear/mock, leaving untouched" % label)

    if args.dry_run:
        for n, new_state, st in updated:
            print(
                "would update: %s %s -> %s (%s)"
                % (n["id"], n.get("state"), new_state, st.get("name"))
            )
        print(
            "dry-run: %d would update, %d unchanged, %d not found"
            % (len(updated), unchanged, len(not_found))
        )
        return

    if not updated:
        print("0 updated, %d unchanged, %d not found" % (unchanged, len(not_found)))
        return

    date = today()
    journal = data.setdefault("journal", [])
    for n, new_state, st in updated:
        n["state"] = new_state
        journal.append(
            {
                "date": date,
                "node": n["id"],
                "i": "\U0001F504",  # 🔄
                "t": "Linear: %s → %s" % (n["label"], st.get("name")),
            }
        )
    journal.sort(key=lambda e: e.get("date", ""), reverse=True)

    backup_path = save_data(base_dir, data)
    print("backup: %s" % backup_path)
    print("%d updated, %d unchanged, %d not found" % (len(updated), unchanged, len(not_found)))
    run_build(base_dir)


# ---------------------------------------------------------------- recover --
def _unescape_builder_html(s):
    # Inverse of build_q3.py's prompt escaping:
    #   .replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')
    # Must undo in reverse order (last-applied first) for exact round-trip.
    return s.replace("&gt;", ">").replace("&lt;", "<").replace("&amp;", "&")


def _extract_between(html_text, prefix, suffix, label, missing):
    idx = html_text.find(prefix)
    if idx == -1:
        missing.append(label)
        return None
    start = idx + len(prefix)
    end = html_text.find(suffix, start)
    if end == -1:
        missing.append(label + " (no closing anchor)")
        return None
    return html_text[start:end]


def cmd_recover(args, base_dir):
    html_path = args.from_html
    if not os.path.isabs(html_path):
        html_path = os.path.join(base_dir, html_path)
    if not os.path.isfile(html_path):
        die("HTML file not found: %s" % html_path)
    with open(html_path, "r", encoding="utf-8") as f:
        html_text = f.read()

    out_dir = args.out or base_dir
    os.makedirs(out_dir, exist_ok=True)

    missing = []
    warnings = []
    data = {}

    # The prompt (also embedded in this HTML, documenting its own format) can
    # mention literal "const NAME=" text too. Anchor all const lookups to the
    # real <script> data block (after the LAST <script> tag) so we never
    # match documentation prose instead of actual data.
    script_marker = "<script>\nconst RITUALS="
    script_idx = html_text.find(script_marker)
    if script_idx == -1:
        die("recover: could not locate the data <script> block (marker %r not found) in %s" % (script_marker, html_path))
    script_text = html_text[script_idx:]

    # 1. `const X=<json>;` lines.
    for js_name, key in RECOVER_CONSTS:
        m = re.search(r"const %s=(.*?);\n" % js_name, script_text, re.DOTALL)
        if not m:
            missing.append("const %s" % js_name)
            continue
        try:
            data[key] = json.loads(m.group(1))
        except json.JSONDecodeError as e:
            die("const %s is not valid JSON: %s" % (js_name, e))

    # META -> narrativa + meta.updated
    m = re.search(r"const META=(.*?);\n", script_text, re.DOTALL)
    if not m:
        missing.append("const META")
    else:
        try:
            meta_obj = json.loads(m.group(1))
        except json.JSONDecodeError as e:
            die("const META is not valid JSON: %s" % e)
        data["narrativa"] = meta_obj.get("narrativa")
        data["meta"] = {"updated": meta_obj.get("updated")}

    # 2. Templates: <pre id="tpl-*" style="display:none">...</pre>
    templates = {}
    for tpl_key, prefix in RECOVER_TPL_ANCHORS.items():
        content = _extract_between(html_text, prefix, "</pre>", "template %s" % tpl_key, missing)
        if content is not None:
            templates[tpl_key] = _unescape_builder_html(content)
    data["templates"] = templates

    # 3. Prompt: <pre id="promptText" ...>\n<escaped prompt></pre>
    idx = html_text.find('<pre id="promptText"')
    if idx == -1:
        missing.append("promptText pre block")
        prompt_txt = None
    else:
        gt = html_text.find(">", idx)
        start = gt + 1
        if start < len(html_text) and html_text[start] == "\n":
            start += 1  # skip the template's own structural newline
        end = html_text.find("</pre>", start)
        if end == -1:
            missing.append("promptText closing </pre>")
            prompt_txt = None
        else:
            prompt_txt = _unescape_builder_html(html_text[start:end])

    # 4. Tabs.
    tabs = {}
    for tab_key, (prefix, suffix) in RECOVER_TAB_ANCHORS.items():
        content = _extract_between(html_text, prefix, suffix, "tab %s" % tab_key, missing)
        if content is not None:
            tabs[tab_key] = content
    data["tabs"] = tabs
    if "kpis" in tabs:
        warnings.append(
            "tabs.kpis recovered AS-RENDERED (evidence lines already inlined via "
            "@EVIDENCE@ expansion); evidence=[] — the original per-item evidence "
            "list cannot be reconstructed from the HTML."
        )
    data["evidence"] = []

    # 5. Footer: "N nodos · M relaciones · fuentes: <fuentes> · <updated>"
    m = re.search(r'<div class="tb-s">(.*?)</div>', html_text, re.DOTALL)
    if not m:
        missing.append("footer (tb-s)")
    else:
        fm = re.search(r"fuentes: (.*) · (\d{4}-\d{2}-\d{2})$", m.group(1))
        if not fm:
            missing.append("footer fuentes/updated pattern")
        else:
            data.setdefault("meta", {})["fuentes"] = fm.group(1)
            if data["meta"].get("updated") and data["meta"]["updated"] != fm.group(2):
                warnings.append(
                    "meta.updated mismatch: META=%r vs footer=%r (using META's)"
                    % (data["meta"]["updated"], fm.group(2))
                )

    if missing:
        die(
            "recover: missing required piece(s) in %s:\n  - %s"
            % (html_path, "\n  - ".join(missing))
        )

    out_data_path = os.path.join(out_dir, "q3-data.recovered.json")
    with open(out_data_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)

    out_prompt_path = os.path.join(out_dir, "q3-prompt.recovered.txt")
    with open(out_prompt_path, "w", encoding="utf-8") as f:
        f.write(prompt_txt or "")

    print("recovered from: %s" % html_path)
    print("wrote: %s" % out_data_path)
    print("wrote: %s" % out_prompt_path)
    print(
        "summary: %d nodes, %d edges, %d rituals, %d lenses, %d done_log, %d journal"
        % (
            len(data.get("nodes", [])),
            len(data.get("edges", [])),
            len(data.get("rituals", [])),
            len(data.get("lenses", [])),
            len(data.get("done_log", [])),
            len(data.get("journal", [])),
        )
    )
    for w in warnings:
        print("warning: %s" % w)


# ------------------------------------------------------------------ main ---
def build_parser():
    p = argparse.ArgumentParser(description="Mechanical update CLI for q3-data.json")
    p.add_argument(
        "--dir",
        default=os.path.dirname(os.path.abspath(__file__)),
        help="directory containing q3-data.json/build_q3.py (default: script's own dir)",
    )
    sub = p.add_subparsers(dest="command", required=True)

    sp = sub.add_parser("touch", help="bump meta.updated + rebuild")
    sp.add_argument("--date", help="YYYY-MM-DD (default: today)")
    sp.set_defaults(func=cmd_touch)

    sp = sub.add_parser("done", help="append a done_log entry + rebuild")
    sp.add_argument("--label", required=True)
    sp.add_argument("--url", required=True)
    sp.add_argument("--date", help="YYYY-MM-DD (default: today)")
    sp.add_argument("--icon", help="default: \U0001F4C4")
    sp.add_argument("--guide", help="mini-guide text")
    sp.add_argument("--nav", help="detail target: node id or ritual id (r-*) for 'ver más'")
    sp.set_defaults(func=cmd_done)

    sp = sub.add_parser("journal", help="append a journal entry + rebuild")
    sp.add_argument("--node", required=True, help="node id (must exist in nodes)")
    sp.add_argument("--text", required=True)
    sp.add_argument("--date", help="YYYY-MM-DD (default: today)")
    sp.add_argument("--icon", help="default: \U0001F4DD")
    sp.set_defaults(func=cmd_journal)

    sp = sub.add_parser("pending-done", help="retire a week_pendings entry (evidence-based) + rebuild")
    sp.add_argument("--key", required=True, help="storage key (1st element of the pending)")
    sp.add_argument("--node", help="node id to journal the closure on")
    sp.add_argument("--note", help="journal text (default: 'Pendiente cerrado: <label>')")
    sp.set_defaults(func=cmd_pending_done)

    sp = sub.add_parser("issue-state", help="set state on an issue/topic satellite node")
    sp.add_argument("--id", required=True, help='"iss-ABC-1234" or bare "ABC-1234"')
    sp.add_argument("--state", required=True, choices=["live", "done"])
    sp.set_defaults(func=cmd_issue_state)

    sp = sub.add_parser("add-issue", help="append a new issue satellite node")
    sp.add_argument("--id", required=True, help="e.g. ABC-1234 (without iss- prefix)")
    sp.add_argument("--parent", required=True, help="theme node id")
    sp.add_argument("--sub", required=True)
    sp.add_argument("--owner", choices=["mine", "other"], default=None)
    sp.add_argument("--state", choices=["live", "done"], default=None)
    sp.add_argument("--icon", help="default: \U0001F4CB")
    sp.set_defaults(func=cmd_add_issue)

    sp = sub.add_parser("note", help="prepend a raw one-line thought to inbox + rebuild")
    sp.add_argument("--text", required=True)
    sp.add_argument("--date", help="YYYY-MM-DD (default: today)")
    sp.set_defaults(func=cmd_note)

    sp = sub.add_parser("memory-add", help="append a distilled note to a memory category + rebuild")
    sp.add_argument("--cat", required=True, help="category id, e.g. personas|lecciones|decisiones|gotchas|preferencias")
    sp.add_argument("--text", required=True)
    sp.add_argument("--refs", help="comma-separated node ids this note references")
    sp.add_argument("--pin", action="store_true")
    sp.add_argument("--date", help="YYYY-MM-DD (default: today)")
    sp.set_defaults(func=cmd_memory_add)

    sp = sub.add_parser("build", help="rebuild only, no mutation")
    sp.set_defaults(func=cmd_build)

    sp = sub.add_parser("status", help="print a compact summary, no rebuild")
    sp.set_defaults(func=cmd_status)

    sp = sub.add_parser("validate", help="check q3-data.json integrity, no mutation")
    sp.set_defaults(func=cmd_validate)

    sp = sub.add_parser("sync-linear", help="sync issue satellite states from Linear (zero-token)")
    sp.add_argument("--dry-run", action="store_true", help="show what would change, mutate nothing")
    sp.add_argument("--mock-file", help="local JSON {identifier: {type, name}} instead of the API")
    sp.set_defaults(func=cmd_sync_linear)

    sp = sub.add_parser(
        "recover",
        help="regenerate q3-data.recovered.json + q3-prompt.recovered.txt from a built HTML (pure parsing, never overwrites live files)",
    )
    sp.add_argument("--from", dest="from_html", required=True, help="path to a built q3-map-2026.html")
    sp.add_argument("--out", help="output directory (default: --dir)")
    sp.set_defaults(func=cmd_recover)

    return p


def main():
    parser = build_parser()
    args = parser.parse_args()
    base_dir = os.path.abspath(args.dir)
    args.func(args, base_dir)


if __name__ == "__main__":
    main()
