# claude-skills

Hand-authored [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills,
shipped as a **plugin marketplace** so every machine updates from one place.

This repo is the single source of truth. Skills used to be symlinked into
`~/.claude/skills/` by hand, which drifted: edits landed on one copy and not the
other, and several skills existed only in the runtime folder with no backup.
Packaging them as a plugin removes the second copy entirely.

## Install

```
/plugin marketplace add NightZpy/claude-skills
```

Then install only the plugins you actually use — the collection is split into six
so nothing loads that you don't want:

| Plugin | Skills |
|---|---|
| `orchestration` | plan-big-execute-small · ask · advisor-tool · decision-inbox |
| `dev-workflow` | review-policy · git-rebase-safety · issue-tracking |
| `personal-ops` | life-os · mac-doctor · npm-supply-chain |
| `design` | tutor · artifact-visual-system · excalidraw · diagram-conventions · proposal-artifact · redesign-existing-projects · web-design-guidelines · vercel-composition-patterns · vercel-react-best-practices |
| `review-tools` | replicate-behavior-report · video-frame-review · docx-comments |
| `context-watch` | no skills: hooks that watch context size (see below) |

```
/plugin install orchestration@claude-skills
/plugin install personal-ops@claude-skills
```

Skills are namespaced by their plugin: `/orchestration:plan-big-execute-small`,
`/personal-ops:life-os`, `/review-tools:video-frame-review`.

Updating, on any machine:

```
/plugin marketplace update claude-skills
/plugin update orchestration
```

## context-watch (hooks, no skills)

Every turn resends the whole context, and quality drops long before the window is full. `context-watch`
lets a session see how full its window is and hand off in time:

- **PostToolUse**: past `CONTEXT_WATCH_WARN_PCT` (default 60) of the model's window it tells the session once
  to wrap up the current subtask. Past `CONTEXT_WATCH_LIMIT_PCT` (default 75) it lets the running work finish,
  starts nothing new, and then writes a handoff and asks you to run `/clear`.
- **UserPromptSubmit**: past the limit, a new prompt is answered by writing the handoff (or, if it exists,
  asking for `/clear`) instead of starting new work.
- **SessionStart** (`clear`): the new session gets the handoff injected and resumes from it. Each handoff is
  used once and must be under 24 h old.

**Window size.** Hooks do not receive it; only the status line JSON does (`context_window.context_window_size`).
For the exact size per model, point your status line at the bridge, or pipe your own status line's input
through it:

```json
"statusLine": { "type": "command", "command": "node ~/.claude/plugins/cache/claude-skills/context-watch/<version>/scripts/context-watch.mjs bridge" }
```

Without the bridge it uses `CONTEXT_WATCH_WINDOW`, else 200k, switching to 1M once usage passes 200k.
Set the variables in the `env` block of `settings.json`.

**Why 60 / 75.** No study gives one percentage where every model degrades. Chroma's
[Context Rot](https://www.trychroma.com/research/context-rot) (18 models, 2025) shows performance falling
steadily with input length; [NoLiMa](https://arxiv.org/abs/2502.05167) (ICML 2025) found 11 of 13 models at
half their short-context score by 32k tokens. Other context monitors settle in the same range: warnings at
60–70% and handoff around 75–85%. Auto-compact fires at the window minus about 13k tokens, so 75% leaves room
for the handoff itself.

State and handoffs live in `$CLAUDE_CONFIG_DIR/context-watch/` (default `~/.claude/context-watch/`), one
handoff per working folder.

## Layout

```
claude-skills/
  .claude-plugin/
    marketplace.json          # marketplace manifest
  plugins/
    orchestration/
      .claude-plugin/
        plugin.json           # plugin manifest (bump version to release)
      skills/
        plan-big-execute-small/
          SKILL.md
    personal-ops/ design/ review-tools/
      skills/
        <skill>/
          SKILL.md
          references/ scripts/ …
```

## Developing a skill

Install the marketplace from the local path instead of GitHub, so edits are live
without a push:

```
/plugin marketplace add ~/Documents/projects/claude-skills
```

Edit under `plugins/<plugin>/skills/<name>/`, reload, and test. When it's
ready: bump `version` in **both** manifests, commit, push. Machines pulling from
GitHub pick it up on the next `/plugin update`.

Do **not** copy skills into `~/.claude/skills/` any more — that's the drift this
layout exists to prevent.

## Adding a new skill

1. Create `plugins/<plugin>/skills/<skill-name>/` — pick the plugin by theme.
2. Add `SKILL.md` with the required frontmatter (`name`, `description`), plus any
   `references/` or `scripts/` it needs.
3. Bump the version in both manifests, commit, push.

## Skills in this collection

**Orchestration & research**
- **plan-big-execute-small** — advisor/executor orchestration: the session model
  plans, verifies and approves; bounded execution goes to cheap fleets (Claude
  subagents, Codex, cc-delegate); Fable advises up front only when the decision
  qualifies.
- **ask** — routes "how does this work" questions to a clean cheap subagent so the
  heavy doc/code reading never lands in the main session's context.
- **replicate-behavior-report** — installs the behavior-report review system in a repo: the E2E behavior-story pipeline, the quality gates and the report generator, with `template/` (generator + runnable fixtures) and `scripts/` bundled.
- **decision-inbox** — one private artifact per project where agents post questions,
  choices, media reviews and blind tests; the human answers from a phone, one item at a
  time (P0–P3 priorities, time-ago, filters, annotated screenshots on time marks), and
  agents read answers back with a low-token `ArtifactData` + `jq` recipe. Ships the page
  template and `scripts/prepare-media.sh`. See its [README](plugins/orchestration/skills/decision-inbox/README.md).
- **advisor-tool** — the server-side advisor tool (`advisor_20260301`) for the
  Claude API: cheap executor consults a stronger advisor mid-generation.

**Daily engineering discipline**
- **review-policy** — code review goes to Codex's own reviewers, never to an inline
  self-review; how to pick the model, read background jobs, and fall back to a
  fresh Claude subagent when Codex can't run.
- **git-rebase-safety** — never lose a commit to a rebase: record what must
  survive, resolve conflicts deliberately, and diff the commit list afterwards.
- **issue-tracking** — open, update and close tracking issues so they stay in sync
  with the work instead of reporting a state that stopped being true.

**Diagrams & design**
- **tutor** — teaching mode: explains anything picture-first, either as a
  self-contained explainer artifact or as inline sketches (pseudocode, call
  trees, mermaid, diffs). Ships its own visual system so every lesson matches.
- **artifact-visual-system** — a ready-made visual system for Claude Artifacts: design
  tokens, component recipes, the mermaid workarounds the runtime needs, and a
  zoomable/full-screen diagram viewer.
- **excalidraw** — generates `.excalidraw` architecture diagrams from codebase
  analysis, with optional PNG/SVG export.
- **diagram-conventions** — when to use sequence vs flow diagrams, typography per
  use case, and the black-background contrast rules.
- **proposal-artifact** — turns a problem into a polished shareable HTML artifact
  (problem + solutions with faithful product mockups).
- **redesign-existing-projects** — audits existing sites/apps, spots generic
  patterns, upgrades them to premium quality without breaking functionality.
- **web-design-guidelines** — reviews UI code against Web Interface Guidelines for
  accessibility and UX. _Authored by Vercel._
- **vercel-composition-patterns** — React composition patterns that scale. _MIT,
  authored by Vercel._
- **vercel-react-best-practices** — React/Next.js performance rules for writing,
  reviewing and refactoring. _Authored by Vercel Engineering._

**Personal ops & tooling**
- **life-os** — builds and daily-updates a personal life operating system as one
  offline-capable HTML artifact (node graph, cockpit, second brain, metrics).
- **mac-doctor** — diagnoses a slow Mac: what's eating RAM/CPU, swap pressure,
  Docker/Colima VM weight, containers in crash loops.
- **npm-supply-chain** — sets up npm supply-chain protection (release-age delays,
  exact pins, committed lockfile).
- **video-frame-review** — turns a screen recording into verbatim frame-by-frame narration plus a diagnosis; bundles `scripts/extract-frames.sh` (ffmpeg wrapper with cadence, time window and the non-ASCII-path fix).
- **docx-comments** — extracts, organizes and tracks review comments from `.docx`
  files.
