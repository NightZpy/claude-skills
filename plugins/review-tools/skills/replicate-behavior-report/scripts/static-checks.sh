#!/usr/bin/env bash
# ── ADAPT (behavior-report-kit) ──────────────────────────────────────────────
# Role: every deterministic gate in one script — also what the pre-commit runs.
# Stable contract: exit nonzero on any finding; fast enough to run per-commit.
# Stack-specific: the whole gate list (ruff/pyright/bandit/xenon/tsc/oxlint
#   here) — swap for your linters/typecheckers; keep gitleaks or equivalent.
# ─────────────────────────────────────────────────────────────────────────────
# Every static/deterministic gate in one place — run by the pre-commit hook and
# as a stage of the review pipeline. Everything must pass; fix findings, never
# skip or weaken a gate (see CLAUDE.md invariants).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "--- ruff (lint + format)"
(cd backend && uv run ruff check -q app tests tests_system scripts migrations &&
  uv run ruff format --check -q app tests tests_system scripts migrations)

echo "--- pyright (backend types)"
(cd backend && uv run pyright | tail -1)

echo "--- bandit (security anti-patterns)"
(cd backend && uv run bandit -q -r app)

echo "--- xenon (complexity ceiling: function<=B, module/average A)"
(cd backend && uv run xenon --max-absolute B --max-modules A --max-average A app)

echo "--- tsc (frontend types)"
(cd frontend && npx tsc -b --noEmit)

echo "--- oxlint"
(cd frontend && npx oxlint --quiet src e2e)

echo "--- design tokens (no raw colors in components)"
./scripts/design-tokens.sh

echo "--- contract types (OpenAPI <-> frontend)"
./scripts/contract-types.sh --check >/dev/null
echo "    in sync"

echo "--- hygiene (dead + duplicated code)"
./scripts/hygiene.sh

echo "--- gitleaks (secrets in history + staged)"
gitleaks git --redact --no-banner 2>/dev/null
gitleaks git --staged --redact --no-banner 2>/dev/null

echo "all static gates green"
