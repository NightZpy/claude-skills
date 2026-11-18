#!/usr/bin/env python3
"""Plan which inbox assets to delete; never deletes anything itself.

Input: the items (and optionally notes/sessions) saved by
  ArtifactData {action:"list", collection:"items", query:{limit:1000}, out_dir:"<dir>"}
Output (stdout, JSON): {"delete": [asset ids], "items": [item ids to mark media_purged_at],
                        "kept_shared": n, "selected": n}
An asset is deleted only when a selected item uses it and no unselected item, note or session does.
Open items are never selected.

  inbox-cleanup.py <dir>/items [--extra <dir>/notes ...] [--status processed,withdrawn]
                   [--from 2026-11-01] [--to 2026-11-10] [--ids '2026-11-03-*,2026-11-17-apagon-v1']
"""
import argparse, glob, json, os, re, sys

ID = re.compile(r'(?:_blob/|"asset_id":\s*")([0-9a-f]{32})')

def load(d):
    out = {}
    for f in glob.glob(os.path.join(d, "*.json")):
        with open(f) as fh:
            out[os.path.basename(f)[:-5]] = json.load(fh)
    return out

def ids_in(doc):
    return set(ID.findall(json.dumps(doc)))

def plan(items, extra, status, frm=None, to=None, ids=()):
    def pick(iid, it):
        if (it.get("status") or "open") == "open" or (it.get("status") or "open") not in status:
            return False
        when = str(it.get("created_at") or iid)
        if frm and when < frm: return False
        if to and when > to + "T23:59:59Z": return False
        return not ids or any(iid.startswith(p[:-1]) if p.endswith("*") else iid == p for p in ids)
    sel = {i for i, it in items.items() if pick(i, it)}
    want, keep = set(), set()
    for i, it in items.items():
        (want if i in sel else keep).update(ids_in(it))
    for doc in extra:
        keep.update(ids_in(doc))
    kill = sorted(want - keep)
    touched = sorted(i for i in sel if ids_in(items[i]) & set(kill))
    return {"delete": kill, "items": touched, "kept_shared": len(want & keep), "selected": len(sel)}

def demo():
    a, b, c = "a" * 32, "b" * 32, "c" * 32
    items = {"x": {"status": "processed", "created_at": "2026-11-01T00:00:00Z", "media": [{"asset_id": a}, {"asset_id": b}]},
             "y": {"status": "open", "media": [{"url": "/_blob/" + b}]},
             "z": {"status": "processed", "created_at": "2026-11-20T00:00:00Z", "media": [{"asset_id": c}]}}
    p = plan(items, [], {"processed"}, to="2026-11-10")
    assert p == {"delete": [a], "items": ["x"], "kept_shared": 1, "selected": 1}, p
    assert plan(items, [{"audio": "/_blob/" + a}], {"processed"}, ids=["x"])["delete"] == []
    assert plan(items, [], {"processed"}, ids=["z*"])["delete"] == [c]

if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        demo(); print("ok"); sys.exit()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("items_dir"); ap.add_argument("--extra", action="append", default=[])
    ap.add_argument("--status", default="processed,withdrawn"); ap.add_argument("--from", dest="frm")
    ap.add_argument("--to"); ap.add_argument("--ids", default="")
    a = ap.parse_args()
    extra = [d for e in a.extra for d in load(e).values()]
    print(json.dumps(plan(load(a.items_dir), extra, set(a.status.split(",")), a.frm, a.to,
                          [x for x in re.split(r"[\s,]+", a.ids) if x]), indent=1))
