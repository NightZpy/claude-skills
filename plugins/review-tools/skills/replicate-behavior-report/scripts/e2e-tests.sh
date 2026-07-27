#!/usr/bin/env bash
# ── ADAPT (behavior-report-kit) ──────────────────────────────────────────────
# Role: boot a disposable full env, run the stories, ALWAYS rebuild the report.
# Stable contract: extra args pass through to the runner; the report HTML is
#   regenerated even on failure; exits with the test status; env torn down on
#   EXIT (Ctrl-C included).
# Stack-specific: the docker-compose boot + HTTP health wait. Desktop app:
#   throwaway user-data dir + firstWindow wait (SKILL.md §10).
# ─────────────────────────────────────────────────────────────────────────────
# E2E run: boots an isolated full stack (frontend 5174 + backend 8002 + tmpfs Postgres,
# project sst-e2e — safe alongside the dev stack), drives the real UI with Playwright,
# regenerates the human review report (frontend/e2e-review-report.html), and always
# tears the stack down. The report is generated even when tests fail — failures are
# exactly what's worth reviewing.
set -euo pipefail
cd "$(dirname "$0")/.."

BACKEND_PORT="${E2E_BACKEND_PORT:-8002}"
FRONTEND_PORT="${E2E_FRONTEND_PORT:-5174}"
COMPOSE=(docker compose -f docker-compose.e2e.yml)

cleanup() {
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> starting isolated stack (backend :${BACKEND_PORT}, frontend :${FRONTEND_PORT})"
# down first: a container lingering from an interrupted run would otherwise be
# reused, and Vite over the macOS bind mount can then serve stale source —
# baselines/screenshots would silently capture old UI.
cleanup
"${COMPOSE[@]}" up -d --build

echo "==> waiting for backend and frontend"
for i in $(seq 1 60); do
  if curl -fsS "http://localhost:${BACKEND_PORT}/health" >/dev/null 2>&1 &&
     curl -fsS "http://localhost:${FRONTEND_PORT}" >/dev/null 2>&1; then
    break
  fi
  if [ "$i" = 60 ]; then
    echo "stack never became healthy; last logs:" >&2
    "${COMPOSE[@]}" logs --tail=30 >&2
    exit 1
  fi
  sleep 2
done

echo "==> running E2E stories"
set +e
(cd frontend && E2E_BASE_URL="http://localhost:${FRONTEND_PORT}" E2E_API_URL="http://localhost:${BACKEND_PORT}" npx playwright test "$@")
status=$?
set -e

(cd frontend && node e2e/build-review-report.mjs) || true
exit $status
