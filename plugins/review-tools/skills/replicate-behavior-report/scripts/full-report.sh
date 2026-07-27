#!/usr/bin/env bash
# ── ADAPT (behavior-report-kit) ──────────────────────────────────────────────
# Role: THE one command — orchestrates every stage in order (SKILL.md §2).
# Stable contract: stage order; metrics.json keys; the never-regress ratchet vs
#   metrics-history.json (coverage/mutation never drop, duplication never rises).
# Stack-specific: each stage's command and the coverage/mutation file locations.
# ─────────────────────────────────────────────────────────────────────────────
# The complete review pipeline: unit tests -> static gates (lint, types,
# complexity, security, hygiene, contract) -> mutation lock -> dependency
# audits -> system tests (with coverage, alembic check, schemathesis fuzzing)
# -> static report data + never-regress invariant -> E2E stories (incl. visual
# checks) -> review report.
set -euo pipefail
cd "$(dirname "$0")/.."

DATA_DIR="frontend/e2e/.report-data"
mkdir -p "$DATA_DIR"

echo "==> [1/7] unit tests"
UNIT_OUT=$(cd backend && DATABASE_URL="sqlite://" JWT_SECRET="test-secret" uv run pytest tests -q 2>&1 | tail -1)
echo "    $UNIT_OUT"
UNIT_PASSED=$(echo "$UNIT_OUT" | grep -Eo '[0-9]+ passed' | grep -Eo '[0-9]+' || echo 0)

echo "==> [2/7] static gates (also enforced by the pre-commit hook)"
./scripts/static-checks.sh | grep -E '^---|duplication|in sync|green' | sed 's/^/    /'

echo "==> [3/7] mutation lock (unit suite vs mutants)"
MUT_OUT=$(./scripts/mutation-tests.sh 2>&1) || { echo "$MUT_OUT" | grep -v '^⠋\|Generating\|Running' | tail -40; exit 1; }
echo "    $(echo "$MUT_OUT" | grep 'mutation score')"

echo "==> [4/7] dependency audits (network: OSV/npm advisories)"
(cd backend && uv run pip-audit --skip-editable 2>&1 | tail -1 | sed 's/^/    /')
(cd frontend && npm audit --audit-level=high >/dev/null && echo "    npm: no high/critical vulnerabilities")

echo "==> [5/7] system tests + coverage"
SYS_OUT=$(./scripts/system-tests.sh 2>&1) || { echo "$SYS_OUT" | tail -250; exit 1; }
echo "$SYS_OUT" | grep -E 'passed|failed|TOTAL' | head -4
SYS_PASSED=$(echo "$SYS_OUT" | grep -Eo '[0-9]+ passed' | head -1 | grep -Eo '[0-9]+' || echo 0)

echo "==> [6/7] migrations / schema / test lists"
./scripts/collect-report-data.sh >/dev/null

node -e "
const fs = require('fs');
const coverage = JSON.parse(fs.readFileSync('backend/coverage.json', 'utf8')).totals;
const mutation = JSON.parse(fs.readFileSync('backend/mutation.json', 'utf8'));
const hygiene = JSON.parse(fs.readFileSync('$DATA_DIR/hygiene.json', 'utf8'));
fs.writeFileSync('$DATA_DIR/metrics.json', JSON.stringify({
  generatedAt: new Date().toISOString(),
  unitTests: $UNIT_PASSED,
  systemTests: $SYS_PASSED,
  coveragePct: coverage.percent_covered,
  statements: coverage.num_statements,
  branches: coverage.num_branches,
  missedLines: coverage.missing_lines,
  mutants: mutation.total,
  mutationKilled: mutation.killed,
  mutationScorePct: mutation.scorePct,
  duplicationPct: hygiene.duplicationPct,
  duplicationClones: hygiene.clones,
}, null, 2));

// Invariant: quality metrics never regress vs the last report the user accepted.
// The gates upstream should make this unreachable — this catches gate tampering.
const prev = JSON.parse(fs.readFileSync('frontend/e2e/metrics-history.json', 'utf8')).at(-1);
if (prev) {
  const drops = [];
  const m = JSON.parse(fs.readFileSync('$DATA_DIR/metrics.json', 'utf8'));
  if (m.coveragePct < prev.coveragePct) drops.push('coverage ' + prev.coveragePct + '% -> ' + m.coveragePct + '%');
  if (typeof prev.mutationScorePct === 'number' && m.mutationScorePct < prev.mutationScorePct)
    drops.push('mutation score ' + prev.mutationScorePct + '% -> ' + m.mutationScorePct + '%');
  if (typeof prev.duplicationPct === 'number' && m.duplicationPct > prev.duplicationPct)
    drops.push('duplication ' + prev.duplicationPct + '% -> ' + m.duplicationPct + '%');
  if (drops.length) {
    console.error('INVARIANT VIOLATED (regression vs last accepted report): ' + drops.join(', '));
    process.exit(1);
  }
  console.log('    invariant holds: coverage ' + m.coveragePct + '%, mutation ' + m.mutationScorePct + '%, duplication ' + m.duplicationPct + '%');
}
"

echo "==> [7/7] E2E stories (incl. visual checks) + review report"
./scripts/e2e-tests.sh "$@"
