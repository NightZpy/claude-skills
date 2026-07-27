#!/usr/bin/env bash
# ── ADAPT (behavior-report-kit) ──────────────────────────────────────────────
# Role: the mutation lock — the fast unit suite must kill every mutant in scope.
# Stable contract: writes mutation.json {total, killed, scorePct}; exit nonzero
#   below 100%. Scope stays explicit (behavior core), never the whole tree.
# Stack-specific: mutmut + its meta parsing (JS/TS: Stryker — parse its JSON
#   report into the same mutation.json shape).
# ─────────────────────────────────────────────────────────────────────────────
# Mutation lock-down: mutmut mutates the behavior core (scope in backend/pyproject.toml,
# [tool.mutmut]) and the fast unit suite must kill every mutant. A survivor is a code
# change the unit suite wouldn't notice — add a unit test to kill it; never loosen the
# gate or widen a pragma to get green. Inspect survivors with: uv run mutmut show <name>
set -euo pipefail
cd "$(dirname "$0")/../backend"

uv run mutmut run

uv run python - <<'EOF'
import json
from pathlib import Path

KILLED_EXIT_CODES = {1, 3}
statuses = {}
for meta in Path("mutants").rglob("*.py.meta"):
    for key, code in json.loads(meta.read_text())["exit_code_by_key"].items():
        statuses[key] = code

total = len(statuses)
killed = sum(1 for code in statuses.values() if code in KILLED_EXIT_CODES)
not_killed = sorted(k for k, code in statuses.items() if code not in KILLED_EXIT_CODES)

Path("mutation.json").write_text(
    json.dumps({"total": total, "killed": killed, "scorePct": round(killed / total * 100, 1) if total else 0.0})
    + "\n"
)
print(f"mutation score: {killed}/{total} killed")
if not_killed:
    print("NOT KILLED — the unit suite would miss these regressions:")
    for name in not_killed:
        print(f"  {name}")
    raise SystemExit(1)
EOF
