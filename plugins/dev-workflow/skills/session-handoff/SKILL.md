---
name: session-handoff
description: Use when the user is about to clear or end a session and wants to continue in a fresh one — "/session-handoff", "haz el handoff", "voy a limpiar", "prepara el handoff", "prompt para un agente limpio", or when context is getting large and work must continue in a new session. Writes a new HANDOFF.md (archiving the old one) and returns a mini prompt to paste into the clean session.
---

# Session handoff

Goal: a fresh agent with zero context resumes exactly where this session stops, and the user never re-explains. Keep it cheap: use what is already in context plus targeted checks (`git log -5`, `git status`, running tasks). Do not re-read the repo.

## Steps

1. **Settle running work.** List background agents/commands still running with their status (finished, running, parked). Finish or explicitly park each. Never claim a result not yet received.
2. **Find the old handoff.** Look for `HANDOFF.md` near the active work, or a path named in CLAUDE.md/roadmap. Archive it as `HANDOFF.old-<YYYY-MM-DD>[-N].md` (`git mv` if tracked, else `mv`; `-N` if the name exists).
3. **Write a NEW `HANDOFF.md` from scratch** (not an edit of the old one). English unless the repo's doc-language rule says otherwise. Short, factual, no narrative; every claim verifiable. Sections:
   1. Where we are: state, what was delivered, verified evidence (paths, ids, commits).
   2. How to run/verify: exact commands, env, paths. Never print secrets.
   3. Decisions made by the user this session (dated).
   4. What changed and why (root causes).
   5. Known open issues/defects, with evidence.
   6. Next steps, ordered.
   7. Rules that still hold.
   8. Pointers to authoritative docs (roadmap, specs).
4. **Update docs the repo requires** (roadmap/status) and commit docs per the repo's git rules (e.g. conventional commits; no AI attribution if the user's CLAUDE.md says so). Never commit to `main` if the rules forbid it.
5. **Reply in the user's language** with: the path of the new handoff, and a mini prompt (max 6 lines) in a code block, ready to paste:

```
Resume <project> at <path>, branch <x>.
Read <handoff path> first (and the roadmap header). Ignore HANDOFF.old-*.
Pending from me: <user verdict/inputs, or placeholder>.
Follow the next steps in order, starting with <first step>.
Talk to me in <language>, short.
```

Use `<placeholders>` only for things only the user knows.
