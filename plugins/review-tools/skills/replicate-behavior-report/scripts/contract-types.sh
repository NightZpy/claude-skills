#!/usr/bin/env bash
# ── ADAPT (behavior-report-kit) ──────────────────────────────────────────────
# Role: keep the cross-language API contract types generated and fresh.
# Stable contract: `--check` exits nonzero when the committed types are stale.
# Stack-specific: openapi-typescript + the OpenAPI exporter. Single-language /
#   native-TS repos: DELETE this stage — the compiler IS the contract.
# ─────────────────────────────────────────────────────────────────────────────
# Contract typing: the frontend's API types are GENERATED from the backend's
# OpenAPI schema (frontend/src/lib/api-schema.d.ts) — never hand-edit that file.
#   ./scripts/contract-types.sh          regenerate after changing the API
#   ./scripts/contract-types.sh --check  fail if the committed types are stale,
#                                        then typecheck the frontend against them
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$PWD/frontend/src/lib/api-schema.d.ts"
SPEC=$(mktemp -t openapi-spec)
trap 'rm -f "$SPEC" "${SPEC}.d.ts"' EXIT

(cd backend && DATABASE_URL="sqlite://" JWT_SECRET="contract" PYTHONPATH=. uv run python scripts/export_openapi.py) > "$SPEC"

if [ "${1:-}" = "--check" ]; then
  (cd frontend && npx --no-install openapi-typescript "$SPEC" -o "${SPEC}.d.ts" >/dev/null 2>&1)
  if ! diff -q "${SPEC}.d.ts" "$OUT" >/dev/null 2>&1; then
    echo "frontend/src/lib/api-schema.d.ts is stale — the backend API changed." >&2
    echo "Run ./scripts/contract-types.sh and fix any frontend type errors." >&2
    diff "$OUT" "${SPEC}.d.ts" | head -30 >&2 || true
    exit 1
  fi
  echo "contract types up to date"
  (cd frontend && npx tsc -b --noEmit)
  echo "frontend typechecks against the contract"
else
  (cd frontend && npx --no-install openapi-typescript "$SPEC" -o "$OUT" >/dev/null 2>&1)
  echo "wrote $OUT"
fi
