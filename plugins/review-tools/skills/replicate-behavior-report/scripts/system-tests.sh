#!/usr/bin/env bash
# ── ADAPT (behavior-report-kit) ──────────────────────────────────────────────
# Role: the system suite against a real deployment shape, with coverage + fuzz.
# Stable contract: coverage gate = 100% line+branch ON THE SCOPE (the gate may
#   live in coverage config, not here); boundary fuzz per SKILL.md §3 —
#   malformed input yields a structured refusal, never a crash; migration round
#   trip if migrations exist; env ALWAYS torn down; coverage flushed by graceful
#   shutdown (`exec` + SIGTERM).
# Stack-specific: compose boot, alembic, schemathesis, coverage tooling.
# ─────────────────────────────────────────────────────────────────────────────
# Full system-test run: boots an isolated docker stack (real Postgres + real migrations,
# backend instrumented with coverage), runs backend/tests_system/ over HTTP, reports
# backend coverage with a hard gate, and always tears the stack down — even on failure.
# Safe to run while the dev stack (docker compose up) is running: different project name,
# ports (5433/8001), and volumes; Postgres is tmpfs so no data survives.
set -euo pipefail
cd "$(dirname "$0")/.."

BACKEND_PORT="${SYSTEST_BACKEND_PORT:-8001}"
BASE_URL="http://localhost:${BACKEND_PORT}"
COMPOSE=(docker compose -f docker-compose.systest.yml)

cleanup() {
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

rm -f backend/.coverage backend/.coverage.systest

echo "==> starting isolated stack (postgres :${SYSTEST_POSTGRES_PORT:-5433}, backend :${BACKEND_PORT})"
# down first: a stack left running (e.g. manual debugging) would otherwise be
# reused with its dirty tmpfs database.
cleanup
"${COMPOSE[@]}" up -d --build

echo "==> waiting for backend"
for i in $(seq 1 60); do
  if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
    break
  fi
  if [ "$i" = 60 ]; then
    echo "backend never became healthy; last logs:" >&2
    "${COMPOSE[@]}" logs backend | tail -40 >&2
    exit 1
  fi
  sleep 2
done

echo "==> migration round trip (downgrade base -> upgrade head)"
# Catches downgrades that leak state (e.g. enum types a re-upgrade would trip on).
# Runs before the tests so they start from the freshly re-seeded schema.
"${COMPOSE[@]}" exec -T backend uv run alembic downgrade base
"${COMPOSE[@]}" exec -T backend uv run alembic upgrade head

echo "==> alembic check (models vs migrations drift)"
"${COMPOSE[@]}" exec -T backend uv run alembic check

echo "==> running system tests"
(cd backend && SYSTEM_TEST_BASE_URL="$BASE_URL" JWT_SECRET="systest-secret" uv run pytest tests_system -q)

echo "==> schemathesis (fuzzing every endpoint from the OpenAPI schema)"
TOKEN=$(cd backend && uv run python -c "
import httpx
print(httpx.post('$BASE_URL/auth/login', json={'cedula': '0000000000', 'password': 'password123'}).json()['access_token'])
")
# Fixed seed keeps the run deterministic; god-mode auth reaches every endpoint.
# Excluded checks (documented decisions, not silences):
# - status_code_conformance: FastAPI doesn't declare our 400/403/404 responses in
#   the OpenAPI spec (candidate improvement: declare `responses=` per endpoint).
# - positive_data_acceptance: schema-valid data can still hit domain rules a JSON
#   schema can't express (duplicate NIT/cedula, password required for new users).
# - negative_data_rejection: query params are strings on the wire, so "wrong-typed"
#   search/sort values are legitimately coerced, never rejected.
# - ensure_resource_availability: our sub-resource 404s are correct REST (PATCH
#   /employees/{id}/user on an unlinked employee), and stateful chains that delete
#   the parent business legitimately 404 the children.
# Capture instead of piping straight into tail: the pipe would swallow both the
# failing cases and schemathesis's nonzero exit code under `set -e`.
SCHEMA_OUT=$(cd backend && uv run schemathesis run "$BASE_URL/openapi.json" -c all \
  --exclude-checks status_code_conformance,positive_data_acceptance,negative_data_rejection,ensure_resource_availability -n 30 --seed 42 \
  -H "Authorization: Bearer $TOKEN" 2>&1) || { echo "$SCHEMA_OUT" | tail -400; exit 1; }
echo "$SCHEMA_OUT" | tail -12

echo "==> stopping backend to flush coverage"
"${COMPOSE[@]}" stop backend >/dev/null

if [ ! -f backend/.coverage.systest ]; then
  echo "coverage data file missing — backend probably didn't shut down gracefully" >&2
  exit 1
fi

echo "==> backend coverage"
(cd backend && uv run coverage combine .coverage.systest >/dev/null && uv run coverage json -o coverage.json -q && uv run coverage report)
