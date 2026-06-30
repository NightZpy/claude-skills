---
name: proposal-artifact
description: >
  Use when the user wants to turn a problem or topic into a polished, shareable
  HTML artifact that explains the problem and lays out proposed solutions with
  faithful product mockups, and have it documented. Triggers: "make/create a
  proposal artifact about X", "hazme un artifact/doc de propuesta", "documenta
  este problema con propuestas y mockups", "turn this into a shareable proposal
  page", "pitch this as a designed doc", or when explaining-a-problem-and-
  proposing-solutions should become a designed, link-shareable page rather than
  a wall of chat text.
---

# Proposal artifact

## Overview
Produces a product-faithful, self-contained HTML "proposal doc" — **problem → approach → numbered proposals (each with a real-product-style mockup) → mapping → sequencing → grounded-in sources** — published as a claude.ai artifact and saved under a `docs/` directory. The user gives the topic; you do the structure, the mockups, and (if needed) the research. Start from the bundled `references/template.html`.

## Workflow
1. **Invoke `frontend-design` first** — this is UI work.
2. **Scope it.** Read any linked thread / PR / context. If the problem or the proposals are unclear, ask ≤3 crisp questions (the problem; research solutions vs. use the ones given; audience). Otherwise just build — keep the user's request friction low.
3. **Ground the proposals.** If you're *proposing* solutions (not just documenting ones the user gave), research real products/apps for precedents and cite them — never invent. Skip the research if the user already supplied the proposals.
4. **Build from the template.** Start from `references/template.html`; fill the sections (below). Mockups must look like the **actual product** (real copy, real component styling, real tabs/badges) — never generic placeholders.
5. **Save to docs.** Write the HTML under a docs directory (e.g. `docs/<area>/<feature>/<feature>.html`). Keep generated docs out of code repos unless that's the project's convention.
6. **Publish.** Render it with the Artifact tool. New topic → new URL; updating one the user links → pass its `url`. Pick a topical emoji favicon and keep it stable across redeploys. Tell the user it's private-by-default and to use **Share** on the artifact page.

## Structure (sections)
- **Header** — eyebrow (`<Org/Product> · <area> · Proposal`), big title with one `<em>`-highlighted word, lede (problem + key constraint), meta row (source thread, builds-on, constraint).
- **Problem** — numbered pain cards; optionally a "today" mockup showing the gap.
- **Approach** — the guiding principle + explicit constraints (e.g. "pragmatic only", "no full rewrite").
- **Proposals** (numbered) — each one: an effort/phase tag, a **faithful product mockup** (browser-frame chrome), a one-line "why" caption, and a grounded-in real example.
- **Maps to the pains** — table: pain → proposal.
- **Sequencing** — phase cards (now / next / optional).
- **Footer** — grounded-in sources, what's explicitly out of scope, the source-of-truth doc path.

## Design conventions
- CSS + component classes live in `references/template.html` (browser frame, pain cards, dialog/modal mockup, flow diagram, table, phase cards, status/lock bars, intent radio-cards, captions). Reuse them; don't re-derive.
- **Artifact fragment format**: start at `<title>` + `<style>` + content. NO `<!doctype>`, `<html>`, `<head>`, `<body>` — the Artifact tool wraps it at publish.
- **Self-contained** (the artifact CSP blocks external hosts): system font stack, no Google Fonts/CDN, inline everything, emoji-only favicon.
- Faithful tokens: a brand accent (the template defaults to violet `#8b5cf6` — swap it for the product's brand color); green = deployed/ok; amber = draft/action-needed; light theme; subtle staggered rise-in on load. Match the product's UI copy language; surrounding annotations can match the user's language.

## Common mistakes
- Generic/abstract mockups instead of product-faithful ones (use real tabs, real copy, real badges).
- Adding `<!doctype html>` / `<html>` / `<body>` — breaks artifact rendering.
- External fonts or CDN assets — blocked by CSP; the page renders broken.
- Writing the generated doc inside a code repo instead of a docs directory.
- Walls of prose where a mockup or a table would land the proposal faster.
