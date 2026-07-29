---
name: ask
description: Use when the user asks how/what/where/why about how a system works (the current repo OR a documented dependency, e.g. "how does the retry loop work", "what does X command do", "where is Y configured", "why did this trace fail"). Delegates the doc/code research to a CLEAN background subagent with an auto-picked cheap model (haiku for lookups, sonnet for reasoning) so the heavy reading never runs in the main session's (possibly huge) context. NOT for editing code, building, or multi-step tasks.
---

# ask — answer a "how does X work?" question in a clean, cheap subagent

The user wants an explanation, not a change. You stay the **orchestrator**: you do NOT read the docs/code
yourself. You dispatch ONE fresh subagent that reads in a clean, small context and returns a short cited
answer. This is the whole point — never burn the main session's large context just to answer a question,
and never make the user pick a model.

## When to use
- "how does X work / what is Y / where is Z / why did W happen / explain the flow" about the current repo
  or a **documented dependency** (a library/service this repo integrates, asked about from the repo that consumes it).
- NOT for: editing files, running builds, multi-step implementation. Those are normal work, not `ask`.
- If you already know the answer from the conversation and it needs **no** doc/code reading, just answer
  inline — don't spawn a subagent for a one-liner you already have.

## Steps (you, the main agent)

### 1. Resolve the grounding doc
Find the doc the subagent should read FIRST:
1. **Personal grounding registry**, `~/.claude/ask-registry.md` if it exists — a subject → absolute-path
   table (e.g. *a platform and its SDK* → its Q&A doc). Use it when the question is about a documented
   dependency, **even from another repo**: that is what lets you ask about a dependency from the repo that
   consumes it. No such file? Skip to 2.
2. Else the **current repo's** `CLAUDE.md` if it names a Q&A grounding doc.
3. Else: no curated doc — the subagent grounds itself in the repo's `README` + `docs/`, plus a code-graph
   MCP if one is connected for that repo.

### 2. Pick the model by need (you choose — the user never specifies). Cap at sonnet.
- **haiku** → single fact / definition / location / "what does command X do" / "which port / env var" /
  yes-no / "where is this documented". Cheap lookups.
- **sonnet** → "how does the whole <flow> work" / trace or behavior analysis / "why did X happen" /
  architecture / tradeoffs / anything needing synthesis across several files.
- Never go past sonnet for the background agent — cheap, clean answers are the point. If a question truly
  needs opus-level reasoning, answer it yourself instead of delegating.

### 3. Dispatch ONE clean subagent
Call the **Agent** tool with `subagent_type: "Explore"`, `model:` your pick from step 2, and a prompt like:

> Answer this question, grounded in `<grounding-doc-abs-path>` — **read it first**, then the doc map it
> points to, then a code-graph MCP if one is connected for that repo, then targeted file reads only
> if needed. Cite every claim as `doc` or `file:line`. Be terse. Answer in the user's language. Read-only —
> do not edit anything. If unsure, say so and point to the file.
> **Question:** "<the user's exact question>"

Run it **foreground** (the user is waiting on the answer). Use `run_in_background: true` only when the user
explicitly asked for a long/deep research sweep.

### 4. Relay
Return the subagent's answer as-is (it's already terse + cited). Add nothing unless the user asked for more.

## Why this exists
The main session may carry a huge context; reading docs/code there is expensive and pollutes it. A fresh
`Explore` subagent reads in a clean small context and returns only the short answer. (This cheap haiku/sonnet
tiering is intentional and specific to Q&A — it is the deliberate exception to the heavy-work tiering in the
`plan-big-execute-small` skill, where deep reasoning is left untagged so it inherits the 1M-context session
model.)
