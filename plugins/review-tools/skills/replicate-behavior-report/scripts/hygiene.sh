#!/usr/bin/env bash
# ── ADAPT (behavior-report-kit) ──────────────────────────────────────────────
# Role: dead-code + duplication gates.
# Stable contract: writes hygiene.json {duplicationPct, clones, duplicatedLines};
#   exit nonzero on any clone >=70 tokens in prod code. Tests/e2e/generated are
#   excluded by design.
# Stack-specific: knip/jscpd targets and --format list.
# ─────────────────────────────────────────────────────────────────────────────
# Hygiene gates: dead code and copy-paste duplication.
# - knip (frontend): zero unused files/exports/types/dependencies. Backend dead
#   code needs no tool — the system suite's 100% line+branch gate already fails
#   on code nothing executes.
# - jscpd gate: ZERO clones of >=70 tokens in production code (real copy-paste).
# - jscpd metric: duplicated-line % at >=50 tokens (sensitive scan) — written to
#   the report data and ratcheted (never rises) by full-report.sh.
# Tests/e2e are excluded on purpose: stories and fixtures repeat by design.
# api-schema.d.ts is excluded too: it's GENERATED (openapi-typescript) — its
# repetition is the generator's output shape, grows with every endpoint, and
# can never be refactored by hand (the file must not be hand-edited).
set -euo pipefail
cd "$(dirname "$0")/.."

DATA_DIR="frontend/e2e/.report-data"
mkdir -p "$DATA_DIR"

echo "--- knip (unused files / exports / dependencies)"
(cd frontend && npx knip)
echo "    clean"

echo "--- jscpd gate (production code, min-tokens 70)"
npx --prefix frontend jscpd backend/app frontend/src \
  --ignore "**/api-schema.d.ts" \
  --format "python,typescript,tsx" --min-tokens 70 --threshold 0 --reporters console >/dev/null
echo "    clean"

echo "--- jscpd metric (sensitive scan, min-tokens 50)"
rm -f "$DATA_DIR/jscpd/jscpd-report.json"
npx --prefix frontend jscpd backend/app frontend/src \
  --ignore "**/api-schema.d.ts" \
  --format "python,typescript,tsx" --min-tokens 50 --reporters json --output "$DATA_DIR/jscpd" >/dev/null

node -e "
const fs = require('fs');
const stats = JSON.parse(fs.readFileSync('$DATA_DIR/jscpd/jscpd-report.json', 'utf8')).statistics.total;
const hygiene = {
  duplicationPct: Math.round(stats.percentage * 100) / 100,
  clones: stats.clones,
  duplicatedLines: stats.duplicatedLines,
};
fs.writeFileSync('$DATA_DIR/hygiene.json', JSON.stringify(hygiene, null, 2));
console.log('    duplication ' + hygiene.duplicationPct + '% (' + hygiene.clones + ' clones >=50 tokens)');
"
