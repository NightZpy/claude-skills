---
name: issue-tracking
description: Use whenever work starts, changes state, or finishes on anything bigger than a one-line fix — a new feature, a bug report, an idea raised but not finished in the same breath, a blocker hit, a branch or PR opened, a scope change, or work that just got verified. Also use when the user says "abre un issue", "trackea esto", "anota esto para después", "ya está listo, ciérralo", or asks what is pending. Apply this proactively at the START of non-trivial work, not only when the user mentions issues.
---

# Issue tracking

Every non-trivial piece of work gets a tracking issue, kept in sync with reality.
An issue that is opened and never updated is worse than none: it reports a state
that stopped being true.

## Where the tracking lives

Check once per repo: `gh issue list`. If it returns issues (or an empty list on a
repo with issues enabled), GitHub is the tracker. If there is no remote or issues
are disabled, use the repo's living backlog doc (`docs/*-backlog.md` or similar) —
same discipline, different medium.

## Open

Open when the user asks for a feature, reports a bug, or raises an idea that is not
being finished in the same breath.

Search first — near-duplicates fragment the history:

```bash
gh issue list --search "<keywords>" --state all
```

Found one? Comment there instead of opening a second.

**Skip entirely for trivial one-step work**: a typo, a rename, a one-line fix. Just
do it.

## Update

One comment per meaningful state change: a decision taken, a blocker hit, the
branch/commit/PR link, a scope change. Not a play-by-play of every step — the issue
is a record someone reads later, not a log.

## Close

Close only when the work is done **and verified**, via the PR/commit (`Closes #N`)
or `gh issue close` with a one-line result.

Same evidence bar as any completion claim: never close on "should work". If you
cannot point at a passing test, a run, or an observed behavior, the issue stays
open.

## Reopen and re-scope

Something regressed, or the ask changed? Reopen and comment what changed. Do not
file a fresh issue for the same thread of work — the history is the value.

## Writing style

Follow the repo's language and tone (check existing issues and the CHANGELOG;
default to English). No AI attribution, same rule as commits.

The issue is the **tracker**, the CHANGELOG is the **record**. A shipped feature
updates both; neither replaces the other.
