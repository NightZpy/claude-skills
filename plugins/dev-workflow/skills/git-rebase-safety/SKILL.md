---
name: git-rebase-safety
description: Use when about to rebase, resolve rebase conflicts, or run any git operation that can silently drop commits — `git rebase`, `git rebase --continue`, `git rebase --skip`, `git pull --rebase`, `git reset --hard`, `git push --force`, cherry-pick chains, squashing, or "the branch has conflicts with main". Also use when a rebase already went wrong and commits or features appear to have vanished. Invoke this BEFORE running the rebase, not after the history is already rewritten.
---

# Git rebase safety

Rebasing rewrites history. A dropped commit does not announce itself: the rebase
reports success, the branch looks fine, and the missing feature is discovered days
later. This skill exists because that already happened and recovery was painful.

## The one rule

**Never `git rebase --skip`.** It discards the commit being applied. There is no
prompt, no warning, and nothing in the reflog that says "you lost work here" —
`--skip` is the single command that silently deletes a commit mid-rebase.

If a commit conflicts, resolve the conflict. If the commit is genuinely obsolete,
stop the rebase and say so out loud before dropping it deliberately.

## Before you start

Record what must survive. This is the check the whole skill hangs on:

```bash
git log --oneline <branch> ^<base> > /tmp/rebase-expected.txt
wc -l /tmp/rebase-expected.txt
```

Also leave yourself an exit: `git branch backup/<branch>-pre-rebase` costs nothing
and turns an unrecoverable mistake into a `git reset --hard backup/…`.

## Resolving conflicts

Read every conflict. Decide what the code should do, not which side is shorter.

- **Never** `git checkout --theirs .` or `--ours .` across the whole tree. Applied
  blind, it discards one side of every conflicting file at once.
- Preserve *intended behavior* from both sides. That is not the same as keeping
  both hunks: if one side deliberately deleted a function, the resolution is the
  deletion, not a merge that resurrects it.
- Unsure what a conflict means? **Ask the user before continuing.** A paused rebase
  is free; a wrong resolution is discovered in production.

## After every rebase — mandatory

```bash
git log --oneline <branch> ^<base> | diff /tmp/rebase-expected.txt - && echo "COMMITS OK"
```

Never claim the rebase succeeded on "it finished without errors". The rebase
finishing is not evidence; the commit list matching is. If commits are missing,
`git reflog` still has the pre-rebase HEAD — recover before doing anything else.

## Destructive operations need confirmation

`git reset --hard`, `git push --force`, `git rebase --skip`, `git clean -fd`,
branch deletion: state what will be lost and get an explicit go-ahead. Prefer
`--force-with-lease` over `--force` when pushing a rebased branch.

## Red flags — stop

- "The conflict is trivial, I'll take theirs" → read it anyway.
- "`--skip` will just move past this one" → it deletes it.
- "The rebase completed, so it worked" → run the commit diff.
- "I'll verify the commits at the end of the task" → verify now; later you cannot
  tell a lost commit from one that never existed.
