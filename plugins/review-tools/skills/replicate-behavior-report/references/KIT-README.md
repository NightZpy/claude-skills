# behavior-report-kit

**Don't trust what the agent *says*; trust what the report *shows*.**

A reusable kit to install the **Behavior Report** review system in any repo: an async
review pipeline where the product owner never clicks through the app and never watches a
terminal. Every feature ships as **behavior stories** — E2E tests whose titles are
plain-language behavior sentences, narrated with captioned screenshots and a GIF of the
real interaction — compiled into ONE self-contained HTML report published as a Claude
Artifact at a permanent URL. The owner reviews from their phone; hard quality gates and a
never-regress ratchet keep the report honest by construction.

## What's in this repo

```
REPLICATION-PROMPT.md  START HERE — field-tested v2 prompt for a coding agent: greenfield
                       mode (all gates hard from commit 1) AND existing-codebase mode
                       (staged gates, scope, burn-down), Electron appendix, Playwright/bash
                       gotchas, artifact publishing mechanics, review layering, build order
SKILL.md               the base spec: stage contracts, tool swap table, features.json
                       schema, report generator spec, story rules, hard rules, mutation
                       playbook — the v2 prompt amends it
template/               the STANDARD report generator (build-review-report.mjs, field-tested
                       in production) — copy it, fill in its CONFIG block, don't re-author
                       from SKILL.md §6 prose; includes sample-data/ for a no-suite smoke run
scripts/               reference pipeline implementation (web stack: FastAPI+Postgres /
                       Vite+TS) with a per-file ADAPT header: role, stable contract, and
                       exactly what to swap for your stack
```

## How the system works

### The feature lifecycle

1. The owner asks for a feature, in their own words.
2. The agent writes **proposed behaviors** into `features.json` first — the spec, quoting
   the owner's words (`askedFor`) — and shows a compact list for approval. Spec before code.
3. The agent builds the feature, then writes its **stories**: Playwright tests that drive
   the REAL app, taking captioned screenshots (`snap()`) and recording video → GIF.
4. One command runs the whole pipeline (gates → stories → report HTML).
5. The report is published as a new **labeled version at the same permanent artifact URL**.
6. The owner reviews it (phone is enough). If satisfied → `--accept`: proposed behaviors
   flip to approved and content baselines are recorded.
7. The next report only embeds what's NEW / CHANGED / failing — approved unchanged stories
   reference previous artifact versions, so the file never outgrows the ~16 MiB cap.

### Behavior stories

A story's title IS a behavior sentence ("opening the app shows the window ready to chat"),
and it must match the `features.json` behavior title EXACTLY — so the promise and the
proof cannot drift apart silently. Every story carries: captioned screenshots (present
tense, specific, honest — oddities go in the caption, not under the rug), a GIF of the
real interaction (slowed 2.5× for readability), an "off-camera preparation" list (data
seeded via API, never through the UI), and its terse `done` conditions. Every feature
ships a happy-path story AND at least one `@edge` story.

### The badges (the honesty machine)

| Badge | Meaning |
|---|---|
| PASS / FAIL | the story's real outcome; failing runs still produce (and are worth publishing) a report with errors expanded |
| NEW | first time seen, or not yet accepted |
| CHANGED | an approved story's content hash drifted — look at it again |
| PROPOSED | behavior not yet approved by the owner |
| NO STORY | red: a promise in the spec with no proof — "the feature may exist; this report can't vouch for it" |
| UNSPECIFIED | a test exists with no agreed behavior behind it |
| HAPPY PATH / EDGE CASE | which side of the feature the story exercises |

NO STORY and UNSPECIFIED don't fail the pipeline — but they may never be published
silently. Quietly rewording an approved behavior surfaces as NO STORY + UNSPECIFIED:
that's the system catching you, working as designed.

### The gates (layered, deterministic first)

1. **Deterministic gates** — non-negotiable mechanics: type-check, lint/hygiene, secrets
   (gitleaks), design-token adherence (no raw hex), duplication (jscpd: zero clones ≥70
   tokens in prod code + a ratcheted metric), dead code (knip), dependency audit.
2. **Test gates** — a milliseconds-fast unit suite; a system suite against the real
   deployment shape with **100% line+branch coverage on the project scope**; and the
   **mutation lock**: the tooling breaks your code on purpose in hundreds of ways (swaps a
   `+` for a `-`, deletes a condition) and the unit suite must scream every time — a
   surviving mutant means a missing test. Gate = 100% killed.
3. **Boundary fuzzing** — hostile/malformed input at your trust boundary (HTTP API via
   schemathesis, or an internal tool seam via property-based tests) must yield a
   structured refusal, never a crash.
4. **Judgment review** — the pipeline has no LLM reviewer of its own: slot your code-review
   rule (Codex/Claude/…) BEFORE publishing, so the artifact always shows post-review code.
   The owner's review of the artifact is the final, human layer.

**Never-regress ratchet**: vs. the last report the owner accepted, coverage and mutation
score may never drop and duplication may never rise. It exists to catch gate tampering —
the gates upstream should make it unreachable. A gate that was accepted is never lowered;
in existing codebases, gates that were never on yet are *staged* (run best-effort, report
honest PENDING with real counts) and turned on one at a time — staged ≠ lowered.

## How to make it work

### Requirements

- **Playwright** (`@playwright/test`) in the target repo — for Electron apps it's often
  already there (VS Code forks ship it).
- **ffmpeg** on the machine (system install preferred over `ffmpeg-static`).
- Stack-specific gate tools per the swap table in `SKILL.md` §3 (Stryker/mutmut, jscpd,
  knip, gitleaks, …) — installable lazily as gates turn on.
- **Claude Code CLI authenticated via claude.ai login** (Pro/Max/Team/Enterprise) for
  artifact publishing — the capability is built in; API-key sessions can't publish.

### Install (once per repo)

1. Copy this kit next to (or into) the target repo.
2. Open a coding agent (e.g. Claude Code) inside the target repo and paste
   **`REPLICATION-PROMPT.md`** in full.
3. The agent picks the mode — **A greenfield** (every gate hard from commit 1, spec starts
   with feature #1) or **B existing codebase** (staged `GATES_ON`, project scope file,
   burn-down inventory of existing features) — and builds everything per the prompt's
   build order: stories first against the real app, pipeline scripts, the report
   generator, then the in-repo operating skill so any future agent runs the system without
   this kit.
4. Definition of done: the one command runs green end-to-end on a demo feature
   (happy + `@edge`), the report renders with correct badges + legend, `--accept`
   round-trips clean, and the first publish mints the permanent artifact URL (pin it in
   the operating skill immediately).

### Operate (day 2, forever)

```
./run.sh report            # or scripts/full-report.sh — the ONE command:
                           # gates → stories → report HTML (always regenerated, even red)
# publish the HTML as a new labeled version at the ONE artifact URL
# owner reviews on their phone
./run.sh report accept     # exactly once, after the owner's review
```

Hard rules: never hand-edit `review-state.json`/`metrics-history.json`; never lower an
accepted gate, skip failing tests, or delete scenarios to get green; one artifact URL, one
favicon; ask before every `git commit`; **nothing is declared done in chat that the report
doesn't show.**

## Provenance

Extracted from a web stack (FastAPI + Postgres / Vite + TS), where the system was invented,
and field-tested end-to-end on a VS Code fork / Electron desktop app — the hardest
replication case: existing codebase, staged gates, Playwright
`_electron.launch`, throwaway user-data-dir isolation. Every gotcha from that replication
is baked into `REPLICATION-PROMPT.md`.
