#!/usr/bin/env bash
# ── ADAPT (behavior-report-kit) ──────────────────────────────────────────────
# Role: gather the non-E2E report inputs into $E2E_DIR/.report-data/.
# Stable contract: writes unit-tests.txt, system-tests.txt, fixtures.json, and
#   (only if the stack has a DB) schema.json + migrations.json — the generator
#   hides the Database section when those are absent.
# Stack-specific below (reference = FastAPI + Postgres): alembic offline SQL, the schema
#   exporter, pytest --collect-only for test ids, the fixture file list.
# ─────────────────────────────────────────────────────────────────────────────
# Collects the non-E2E inputs of the review report into frontend/e2e/.report-data/:
# per-migration SQL (alembic offline mode — no database needed), the model schema
# for the ER diagram, and the collected test id lists of both backend suites.
set -euo pipefail
cd "$(dirname "$0")/.."

DATA_DIR="frontend/e2e/.report-data"
mkdir -p "$DATA_DIR"

# offline alembic only uses the URL for the dialect; nothing connects
export DATABASE_URL="postgresql+psycopg://offline:offline@localhost/offline"
export JWT_SECRET="offline"

echo "==> exporting model schema"
(cd backend && PYTHONPATH=. uv run python scripts/export_schema.py) > "$DATA_DIR/schema.json"

echo "==> rendering migration SQL"
(cd backend && uv run python - <<'PY') > "$DATA_DIR/migrations.json"
import io
import json
import sys
from contextlib import redirect_stdout

from alembic.config import Config
from alembic.script import ScriptDirectory
from alembic import command

config = Config("alembic.ini")
script = ScriptDirectory.from_config(config)

migrations = []
for revision in reversed(list(script.walk_revisions())):  # oldest first
    span = f"{revision.down_revision or 'base'}:{revision.revision}"
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        command.upgrade(config, span, sql=True)
    migrations.append(
        {
            "revision": revision.revision,
            "down_revision": revision.down_revision,
            "message": revision.doc,
            "sql": buffer.getvalue(),
        }
    )

json.dump(migrations, sys.stdout, indent=2)
PY

echo "==> collecting test ids"
(cd backend && DATABASE_URL="sqlite://" uv run pytest tests --collect-only -q 2>/dev/null | grep '::' || true) > "$DATA_DIR/unit-tests.txt"
(cd backend && DATABASE_URL="sqlite://" uv run pytest tests_system --collect-only -q 2>/dev/null | grep '::' || true) > "$DATA_DIR/system-tests.txt"

echo "==> collecting test fixtures"
python3 - <<'PY' > "$DATA_DIR/fixtures.json"
import json
import sys

fixtures = [
    ("System test fixtures (real Postgres over HTTP)", "backend/tests_system/conftest.py"),
    ("Unit test fixtures (in-memory SQLite)", "backend/tests/conftest.py"),
    ("E2E seeding helpers (drive the real API)", "frontend/e2e/helpers.ts"),
]
json.dump(
    [{"title": t, "path": p, "code": open(p).read()} for t, p in fixtures],
    sys.stdout,
    indent=2,
)
PY

echo "report data collected in $DATA_DIR"
