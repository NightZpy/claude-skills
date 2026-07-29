---
name: issue-tracking
description: Use whenever work starts, changes state, or finishes on anything bigger than a one-line fix — a new feature, a bug report, an idea raised but not finished in the same breath, work actually beginning, a blocker hit, a branch or PR opened, a scope change, work that just got verified, or a request being dropped or rejected. Also use when the user says "abre un issue", "trackea esto", "anota esto para después", "ya está listo, ciérralo", "esto ya no lo vamos a hacer", or asks what is pending. Apply this proactively at the START of non-trivial work, not only when the user mentions issues.
---

# Issue tracking

Every non-trivial piece of work gets a tracking issue whose state matches reality.
An issue that is opened and never moved is worse than none: it reports a state that
stopped being true, and the next person trusts it.

## Where the tracking lives

Check once per repo: `gh issue list`. If it works, GitHub is the tracker. If there
is no remote or issues are disabled, use the repo's living backlog doc
(`docs/*-backlog.md` or similar) — same states, different medium.

**Skip all of this for trivial one-step work**: a typo, a rename, a one-line fix.
Just do it.

## The state machine

| State | Enter it when | Command |
|---|---|---|
| **Open** | The user asks for a feature, reports a bug, or raises an idea not being finished in this same breath | `gh issue create` |
| **In progress** | You actually start — the branch is created, the first file is touched. Not when the issue is filed | `gh issue edit N --add-assignee @me --add-label "in progress"` |
| **Blocked** | Work stops on something outside this issue: a decision you need, a broken dependency, another issue | comment saying **what** blocks it and **who** unblocks it, `--add-label blocked` |
| **Closed — completed** | Done **and** verified | `gh issue close N --reason completed --comment "<one-line result>"` |
| **Closed — not planned** | The work will not happen: rejected, obsolete, duplicate, out of scope | `gh issue close N --reason "not planned" --comment "<why>"` |
| **Reopened** | It regressed, or the ask came back | `gh issue reopen N` + a comment saying what changed |

Labels are a repo convention, not a given. Check with `gh label list` before using
one; if the repo has no equivalent label, a comment carries the same state and
costs nothing. Never invent a label taxonomy the repo does not already use.

## Open

Search before creating — near-duplicates fragment the history:

```bash
gh issue list --search "<keywords>" --state all
```

Found one? Comment there instead of opening a second. Found a closed one describing
the same thing? Reopen it rather than filing a fresh issue.

## In progress means started, not planned

The transition to *in progress* is the one most often skipped, and it is the one
that makes the tracker readable: an issue list where everything is "open" tells you
nothing about what is actually being worked on right now.

Move it when work begins, and put the branch name in a comment. When the PR opens,
link it (`Closes #N` in the PR body ties them and closes on merge).

## Closing — the two reasons are not interchangeable

`completed` means it shipped. `not planned` means it will not. Picking the wrong
one poisons every future search: a rejected idea closed as `completed` looks like
delivered work months later.

**Never close on "should work".** Same evidence bar as any completion claim: point
at a passing test, a run, or an observed behavior. No evidence, no close.

**Never close as `not planned` on your own judgment.** Dropping work the user asked
for is their decision — propose it and get an answer. The exception is a genuine
duplicate, where you close the newer one pointing at the older.

## Update

One comment per meaningful state change: a decision taken, a blocker hit, the
branch/commit/PR link, a scope change. Not a play-by-play — the issue is a record
someone reads later, not a log.

Scope changed materially? Edit the title and body so they describe the work as it
is now, and comment what changed. An issue whose title stopped matching its content
is invisible in search.

## Writing style

Follow the repo's language and tone (check existing issues and the CHANGELOG;
default to English). No AI attribution, same rule as commits.

The issue is the **tracker**, the CHANGELOG is the **record**. A shipped feature
updates both; neither replaces the other.
