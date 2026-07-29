---
name: review-policy
description: Use whenever code needs an independent review — reviewing the working diff before a commit, reviewing a branch or PR before merge, the `requesting-code-review` step of any workflow, "revisa esto", "haz code review", "¿está bien este cambio?", or a security/correctness pass over work that was just written. Use it BEFORE claiming a change is ready to merge. Applies to work the assistant wrote itself, which is exactly when an independent reviewer matters most.
---

# Review policy — Codex reviews, I triage

Code review goes to **Codex**, not to an inline self-review. The reviewer must be
independent: an agent reviewing its own diff in the same context reliably
rubber-stamps it.

The reviewer produces findings. **I triage them and decide what to apply** — a
passing review is not an approval, and neither is a failing one a mandate.

## Resolve the runtime first

```bash
CODEX=$(ls -td ~/.claude/plugins/cache/openai-codex/codex/*/ | head -1)scripts/codex-companion.mjs
```

`ls -td … | head -1` matters — stale plugin versions stay in the cache.

## Preferred path: the native reviewers

Use Codex's own review harness rather than a hand-written brief. It knows how to
scope a diff and what to look for:

```bash
node "$CODEX" review [--base <ref>] [--scope auto|working-tree|branch] [--wait|--background]
node "$CODEX" adversarial-review [focus]
```

Needs a custom brief instead (a specific worry, a subsystem, a non-git artifact)?
Use the `codex:codex-rescue` subagent or the `codex:rescue` skill and pass the
diff or scope explicitly.

## Which model

Read what the account actually has — the catalogue is served per account and
changes without notice:

```bash
jq -r '.models[]?.slug' ~/.codex/models_cache.json
```

Pick by how much the review costs if it is wrong: the mid tier for a normal pass,
the light tier for a quick one, the top tier for correctness-critical, security or
subtle-logic work. Pin `--effort` explicitly — several models default to `low`,
which silently downgrades a hard review. Model missing or rejected with a 400? Drop
to the previous generation in the same cache and note it.

## When Codex cannot run

Usage limit exhausted, CLI error, not logged in, plugin absent — fall back to a
**Claude review in a fresh subagent** (fresh, so it does not inherit the reasoning
that produced the code). Size the model to the difficulty: the deep tier for
correctness-critical, security or subtle-logic passes; the workhorse tier for
lighter ones.

Re-run with Codex once it is available again if the change is still open.

Do **not** reach for an inline self-review or the native `/code-review` while Codex
is available.

## Background jobs — never stay stranded

A background review that goes quiet is not a finished review. Query the runtime
directly instead of waiting on a forwarder:

```bash
node "$CODEX" status --all          # job state + job-id
node "$CODEX" result <job-id>       # findings, once completed
```

| Status | What it means | Do |
|---|---|---|
| `running` | genuinely working; status shows elapsed + progress | report and wait |
| `completed` | findings are ready | `result <job-id>`, triage them |
| `failed` | read the error in `status` | model unsupported → drop a tier and relaunch ONCE; quota exhausted → Codex is down for this run, fall back to Claude |

If a forwarder subagent stops reporting, resume it **once**; if it still does not
deliver, bypass it and read `status`/`result` yourself. Never launch a second
review to replace one that is still running — you pay twice and reconcile two
findings lists.

## Triage is mine

Verify each finding against the actual code before acting on it. Reviewers report
plausible-but-wrong findings, and applying one blindly is how a working change
becomes a broken one. Apply what holds, say what you dismissed and why.
