#!/usr/bin/env bash
# ── ADAPT (behavior-report-kit) ──────────────────────────────────────────────
# Role: ban raw colors outside the token-definition file(s).
# Stable contract: exit nonzero on any violation, listing file:line.
# Stack-specific: the grep patterns + allowed files (Tailwind arbitrary values
#   here; e.g. registerColor / var(--vscode-*) in a VS Code-based app).
# ─────────────────────────────────────────────────────────────────────────────
# Design-system adherence: every color must come from a theme token, never a
# raw hex or an arbitrary Tailwind color value in component code. index.css is
# where the tokens are DEFINED (and the fontsource @imports live), so it's the
# only place hex is allowed; the generated contract types are exempt too.
#
# Pairs with the visual-regression baselines (rendered compliance) and the
# design notes in CLAUDE.md — this catches token drift before it ships.
set -euo pipefail
cd "$(dirname "$0")/../frontend"

# Arbitrary Tailwind color values: bg-[#...], text-[#...], border-[#...], and
# bracketed CSS-var color escapes people reach for instead of a real token.
ARBITRARY=$(grep -rnE '(bg|text|border|ring|fill|stroke|from|via|to|shadow|outline|decoration|accent|caret)-\[#' src --include='*.tsx' --include='*.ts' || true)

# Bare hex literals in TS/TSX (e.g. a color passed as a string prop).
BARE_HEX=$(grep -rnE "['\"]#[0-9a-fA-F]{3,8}['\"]" src --include='*.tsx' --include='*.ts' || true)

FINDINGS="${ARBITRARY}${BARE_HEX}"
if [ -n "$FINDINGS" ]; then
  echo "    design-token violations — use a theme token (index.css), not a raw color:" >&2
  printf '%s\n' "$ARBITRARY" "$BARE_HEX" | grep -v '^$' | sed 's/^/      /' >&2
  exit 1
fi
echo "    all colors come from theme tokens"
