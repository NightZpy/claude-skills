---
name: plan-big-execute-small
description: Orchestration mode - run the current task with the "plan big, execute small" advisor/executor pattern inside this session. The session model (Opus 5) orchestrates, verifies and approves; bounded execution goes to cheap executors (Claude sonnet/haiku, Codex, or cc-delegate once the Claude-usage threshold is crossed); Fable 5 is consulted up front, as a one-shot advisor, only for decisions that qualify. Use when the user invokes /plan-big-execute-small, says "plan big execute small", "patron planner/executor", "advisor pattern", or asks to run a big task with cheap executors under big-model supervision. NOT for trivial tasks (one file, one step) - just do those directly.
---

# Plan Big, Execute Small — in-session orchestration

You (the session model, **Opus 5**) are the **orchestrator, verifier and approver**, always — in every mode, with every fleet. What changes from run to run is only *who types*. The expensive intelligence goes into specifying, reviewing and course-correcting; never into typing mechanical steps.

The pattern applies **always**, whether or not cheap external fleets are available. Crossing a usage threshold swaps the executor fleet; it never swaps the pattern, and it never moves approval off you.

## Step 0 — Bootstrap (ALWAYS, before planning)

Bootstrap procedure in ONE single bash block + one question to the user if applicable:

1. **Usage signal** (proxy, doesn't know the plan's real limit): `npx -y ccusage blocks --json` → from the active block extract `totalTokens`, `burnRate.tokensPerMinute`, `projection.totalTokens`. Indicative threshold: >150M tokens in the active block or burn >800k/min = strong signal.
2. **Pick the delegation mode** from that signal (four modes — see "Delegation modes" below). The closer to the Claude limit / the fewer days to reset, the more leaves the session. Default **Split**; on a strong signal or harness usage warnings, ask via AskUserQuestion **Delegate-led** (recommended) / **Split** / **Claude-led** / **postpone**. No signal and plenty of budget → **Claude-led** without asking. The chosen mode governs the whole run.

   **Two thresholds are in play — don't confuse them.** *This* one (your Claude budget, read from `ccusage` + harness warnings) decides **WHEN cc-delegate enters at all**. The plugin's own threshold is a **monthly USD spend quota per provider** (`cc-delegate setup`, default $10 OpenRouter, alerts ⚠ 80% / 🔴 100%) and only caps **HOW MUCH** it may spend once it's in. cc-delegate cannot see your Claude usage — nothing but you crosses the first threshold.
3. **Verify fleets ONCE** (not per step), in the same bash block:
   - Codex: `CODEX=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs | tail -1); node "$CODEX" setup --json` → `ready` + `auth.loggedIn`.
- cc-delegate: `cc-delegate setup --json` (fallback: `node ~/.claude/plugins/cache/claude-code-delegate/cc-delegate/*/scripts/companion.mjs setup --json`) → `ready` and active providers: the actual shape is `providers.<name>.keyPresent` / `.active` / `.quota` (there is NO field called `configured` nor a list `keys`). Active fleet = some provider with `active:true`. Also read the additive `agentic:{installed,version,serverRunning}` block: `installed:true` = agentic mode (`task --agentic`) is available for tool-requiring bounded steps this run; absent or `installed:false` = text mode only. None active → suggest `! cc-delegate-keys` ONCE and continue without it.
4. **Announce the resulting routing** in 1-2 lines (which fleet covers judgment/execution/mechanical/review in this run) and only then write the PLAN.

Dispatch gotchas learned (don't repeat):
- `codex-companion.mjs task --background ...` responds in **plain text** ("Codex Task started ... as task-XXXX"), NOT JSON — extract the id with grep/sed on that text, never with json.load. `setup`/`status` do accept `--json`.
- `setup --json` with `ready:true` does NOT guarantee quota: the first task may fail with "You've hit your usage limit... try again at <date>". That error marks the Codex fleet as DOWN for the entire run (the date is usually weeks away) — don't retry; move to the next in the chain (cc-delegate if it has keys; if not, Claude or ask the user).
- Cheap real-quota check: dispatch a trivial task ("reply OK") and check `status` before sending long briefs, or read the first `status` of the first real step before dispatching the rest.

## Roles

| Role | Who | What they do |
|---|---|---|
| **Advisor** *(only when the task qualifies)* | **Fable 5**, one-shot subagent | Turns a hard, hard-to-reverse problem into a structured spec: approach, edge cases, constraints. Never executes, never converses, never runs twice |
| Planner | You (Opus 5) | Specifies the task and decomposes it into bounded, verifiable steps — or relays Fable's spec as those steps |
| Executor | Claude subagent (`sonnet`/`haiku`), **Codex**, or **cc-delegate** past the threshold | Executes ONE bounded step and returns evidence |
| Verifier / approver | **You, always** | Checks each result against its criterion, corrects course, synthesizes, approves |

Sonnet is the workhorse executor; Haiku only for genuinely mechanical steps. Judgment (architecture, subtle bugs, security, ambiguous specs) is never handed to an executor: either you do it inline, or — if it meets the bar below — Fable specifies it *before* any code is written.

## When Fable advises — decided UP FRONT, never after a failure

Fable is the most expensive model available, so it is consulted **once, at triage, before planning** — never as a rescue. "I tried, it failed, now I'll call Fable" pays twice for work Fable would have done once; and if the failure came from missing information, a bigger model doesn't fix it either.

**Call Fable when any of these is true** (evaluate before you plan):
- the decision is **hard to reverse** — architecture, data schema, public contract, migration path;
- **being wrong costs far more than tokens** — security, money, data loss, a public interface others will build on;
- the **solution space is wide and the choice determines everything downstream**;
- there is a **real tension between requirements** that someone must resolve before code exists.

None of them → you plan it yourself. In doubt with a cheap-to-reverse decision → you plan it yourself.

**How.** One `Agent` call, `model: 'fable'`, prompt framed as *analyse / specify / identify edge cases* — never "implement". Give it the full problem, ask for a structured spec (numbered decisions, constraints, edge cases, verification criteria). It returns the spec and it's done: **its spec goes straight to the executors as the plan's steps; you don't re-litigate it, you verify the results.** If Fable's spec turns out to be wrong under execution evidence, that's a new triage — bring the evidence back in ONE targeted follow-up, don't start a conversation.

## Available executors: Claude and Codex

Two executor fleets; choose per step. **Verify Codex once at the start of EXECUTE** (not per step): `node ~/.claude/plugins/cache/openai-codex/codex/<version>/scripts/codex-companion.mjs setup --json` → `ready: true` and `auth.loggedIn: true`. If it's not ready, or a task fails due to quota/limit/`model not supported`, **fall through to the Claude equivalent in the table and continue** — note it in the final report, don't stop or retry in a loop.

**Classify each step by difficulty, not by the name of the task.** A step is *mechanical* only when **the correct answer is unique and a command proves it** — it compiles, the tests pass, the grep comes back clean — and nothing has to be decided along the way. A rename across 40 call-sites with edge cases is *not* mechanical; it's standard execution. Misclassification is the real cause of "the cheap model wasn't good enough", so when a step's verification fails, suspect the classification before the model. Retrying at the cheap tier costs cents, so cheap steps may retry freely — that asymmetry is exactly why Fable is decided up front and `deepseek`/`haiku` don't have to be.

| Step type | Codex (if available) | Claude (default/fallback) |
|---|---|---|
| Mechanical (unique answer, command-verifiable) | `gpt-5.6-luna` effort `low` (alternative: `spark` = `gpt-5.3-codex-spark`) | `model: 'haiku'` |
| Standard execution (implement bounded step) | `gpt-5.6-terra` effort `medium`/`high` (alternative: `gpt-5.4`) | `model: 'sonnet'` |
| Review/verification of what was executed | `gpt-5.6-terra` (global rule: review ALWAYS with Codex if available; fallback `gpt-5.5`) | fresh subagent Opus/Sonnet only as fallback |

GPT-5.6 family in Codex (verified jul-2026 with ChatGPT auth): `gpt-5.6-terra` (balanced) and `gpt-5.6-luna` (fast/cheap) **work**; plain `gpt-5.6` and `gpt-5.6-sol` (flagship) return 400 with ChatGPT accounts — Sol is for API accounts only. Ctx 272K.

How to dispatch a Codex executor — two ways:
- **Via subagent** (simple): `Agent` with `subagent_type: 'codex:codex-rescue'` and the brief as prompt; the forwarder makes ONE `task` call. Use `--write` for steps that edit; add `--model X --effort Y` in the brief if you want to pin them (without flags it uses the default from `~/.codex/config.toml`).
- **Via direct runtime** (to parallelize N Codex steps): `codex-companion.mjs task --background --write [--model X] [--effort Y] "<brief>"` per step → save each job-id → continue dispatching Claude in parallel → collect with `status <job-id>` / `result <job-id>`. If `status` = `failed`, read the error: quota/model cause → redispatch that step with the Claude fallback; brief cause → fix the brief and retry ONCE.

Mixing rules:
- Codex executes in the real working tree (not in isolated context): **never two writers (Codex or Claude) on the same files at the same time** — steps that write to different areas can run in parallel; if they share files, sequence them or use worktrees.
- The brief to Codex must be as self-contained as a Claude subagent's, and also explicitly state what evidence to return (Codex doesn't see your plan).
- The final review step follows your hard global rule: Codex first; Claude only if Codex can't run.

### Third fleet: cc-delegate (cheap external models, text + agentic)

cc-delegate is the third executor fleet. **For all its specifics — text vs agentic, which model by capability/price (grounded in the Anthropic-equivalence table), how to write the brief, dispatch, and reading usage/health/advisory signals — invoke the `cc-delegate:using-cc-delegate` skill.** Don't duplicate that logic here; this section only covers how it slots into the orchestration.

Availability (check once at bootstrap, Step 0 already does): `cc-delegate setup --json` → `ready:true` and the additive `agentic:{installed,...}` block. Not installed / no keys → this fleet doesn't exist for the run; suggest `! cc-delegate-keys` ONCE and continue with Claude/Codex, don't stop.

**When it enters:** on crossing the Claude-usage threshold (Delegate-led onward — see the modes table). Below it, cc-delegate is reserved for bulk boilerplate and long-material reads; it isn't a per-step competitor to Claude subagents, it's their replacement once your budget is the binding constraint.

Where it sits vs the other fleets:
- **Text mode** = pure generation with no tools (boilerplate, tests, mechanical refactor of provided code, diff review, long-context reads). Cheapest. Output is NOT applied — you or a cheap subagent apply + verify.
- **Agentic mode** (`task --agentic [--write]`) = the delegate needs to explore the repo, run commands, or edit in place. ~100× a text call but still cheaper than a Claude subagent; use it for tool-requiring bounded steps when Codex is unavailable/out of quota.
- Decisions (design, architecture, security) stay with the orchestrator regardless of fleet.

### Delegation modes (four, driven by the Claude-usage signal)

**cc-delegate is not a fleet that competes step by step — it's what takes over once your Claude budget crosses a threshold.** Below the threshold, execution runs on Claude subagents and Codex. Above it, cc-delegate absorbs what those subagents would have done; deeper still, it also absorbs judgment, and finally the coordination itself. Codex is the exception to the whole scale: it comes out of your subscription quota, so its marginal cost is ~zero and it stays available in every mode (and stays the default reviewer).

You can't read your exact `/usage`; infer the mode from harness usage-limit warnings (most reliable), what the user tells you ("we're at 90%, reset in 3 days"), and the `npx ccusage blocks --json` proxy (>150M active-block tokens or burn >800k/min = strong signal).

| Mode | When | Who executes | You |
|---|---|---|---|
| **Claude-led** | Plenty of budget, far from reset | Claude subagents (`sonnet`/`haiku`) + Codex. cc-delegate only for bulk boilerplate and long reads that would bloat context | do the substantive work yourself; quality-first |
| **Split** *(default)* | Normal | Same, but every bounded step is delegated: codegen, refactors, tests, diff review, research reads | orchestrate + the genuinely hard thinking |
| **Delegate-led** | Near the limit / harness warnings / user says so | **cc-delegate takes over execution**; judgment steps go out too, with all material in `--file`/`--diff` | minimal supervisor: plan once, read distilled evidence, short verdicts — never read raw material, never execute |
| **Lifeboat** | Effectively out of Claude | `cc-delegate orchestrate` runs the loop: plans, dispatches parallel workers in isolated worktrees, merges only clean patches | plan once, then apply + verify what comes back. It never self-approves |

**Which cc-delegate model** for a given step — invoke the **`cc-delegate:using-cc-delegate` skill**; it is the single source of truth and already maps mode × strategy (TEXT/AGENTIC) to exactly one model, using the same four mode names. Don't re-derive it here.

Substitution order within a mode: **Codex** `gpt-5.6-terra`/`luna` while it has quota → **Claude subagent** (`sonnet`/`haiku`) below the threshold, **cc-delegate** above it → the other one as fallback. Review is always Codex first; if Codex is down, `glm` (+ `grok` for a second opinion) via cc-delegate; a Claude review only for security-critical paths.

Announce the active mode at Step 0; step back down once the reset passes or the user says so; note in the final report what ran delegated vs in-session, and on which fleet.

## Flow

### 1. PLAN (you, without delegating)
- **Triage first, before reading anything expensive:** does this task meet the Fable bar above? Yes → one Fable subagent returns the spec, and **that spec becomes the plan's steps directly** — you don't rewrite it, you verify what the executors produce against it. No → you write the plan.
- Read the minimum necessary to specify well (or dispatch 1-2 read-only Sonnet scouts if the map is large).
- Write the plan: **bounded** steps (one deliverable per step), each with: objective, files/scope, expected output, and **how to verify** (command, test, observable criterion).
- Mark dependencies: independent steps are dispatched in parallel; dependent ones, in sequence.
- Present it to the user in 3-6 lines before executing (unless a plan has already been approved).

### 2. EXECUTE (subagents)
- One Agent per step, `model: 'sonnet'` (or `'haiku'` if mechanical). Independent steps → dispatch in parallel in a single message.
- **The executor prompt must be self-contained**: subagents don't see your context. Include exact paths, relevant repo conventions, the expected output, and the verification criterion. Ask for evidence (command output, diff, green test), not assertions.
- Forbidden for the executor: design/architecture decisions, touching outside their scope, "improving" adjacent code. If a step requires a decision, they must report it back, not make it.

### 3. ADVISE (you, on each result)
- Review the report against the step's criterion. Real evidence or assertion?
- Fails or deviates → ONE retry with concrete corrective feedback (what was wrong, what you expected).
- Second failure, or the step turned out to be judgment-heavy → take it back: do it yourself inline, or redispatch without a model tag. **Never to Fable** — a step that failed in execution is an information problem, not a reasoning-capacity one, and paying Fable to redo it means paying twice for work it would have specified once. Fable is decided at triage or not at all.
- One result may invalidate later steps in the plan — adjust the plan before continuing to dispatch, not after.

### 4. VERIFY & SYNTHESIZE (you)
- Run global verification (tests, build, end-to-end flow — skill `verify` if applicable).
- Final summary for the user: what was done, evidence, what was left out.

## Hard rules

- Never dispatch without a written plan: steps without verification criteria produce false "done ✅" reports.
- Never accept a report without verifiable evidence.
- Escalating *within the cheap fleets* is cheap, reworking is expensive: on the second failure of an executor, upgrade the model or do it yourself. Escalating *upward to Fable* is not — that call is made at triage, before any tokens are spent.
- You approve, always. No mode, no fleet and no advisor ever takes the approval step — not `orchestrate`, not Fable, not a passing review.
- Trivial tasks (one file, one step) do NOT use this pattern — do them directly; the orchestration overhead outweighs the savings.

## Pattern economics (from the cookbook, measured)

- **The savings come from keeping raw material out of YOUR context.** Heavy tokens (web pages, logs, large files, codebase sweeps) should be read in the subagent's context, which returns distilled findings. If raw material ends up in the coordinator's context, you paid for orchestration for nothing. In cookbook runs: ~2.5x cheaper and ~3x faster, with 84-98% of input billed at worker rate.
- **Delegation has a fixed cost per subagent** — brief granularity has an optimum. Splitting the same work into more, narrower briefs INCREASES cost. Prefer few substantial steps to many micro-steps.
- **Don't delegate judgment on subtle raw material**: a cheap reader can summarize and miss exactly what mattered (fine document analysis, nuance decisions). You read that yourself.
- **Verify the premise too, not just the steps**: if the plan decomposition starts from your memory (a list, an assumption), spend a cheap step verifying it — the cookbook audited 20 facts perfectly against a list that had one wrong item from memory.

## Origin

Adaptation to the Claude Code harness of the CMA cookbook "Plan Big, Execute Small" (tool-less frontier coordinator + cheap workers with tools, reading in parallel threads and reporting distilled findings) and the API advisor tool. Cookbook: https://github.com/anthropics/claude-cookbooks/blob/main/managed_agents/CMA_plan_big_execute_small.ipynb

Advisor/executor references: Anthropic's advisor strategy (advisor returns a 400-700 token plan, executor keeps control and pays the low rate — https://claude.com/blog/the-advisor-strategy), the Fable-5 advisor/executor write-up (advisor plans only; letting it execute or converse destroys the saving — https://www.mindstudio.ai/blog/advisor-executor-pattern-claude-code-fable-5), and https://arxiv.org/pdf/2510.02453. One deliberate divergence: in Anthropic's version the *executor* decides when to consult the advisor mid-task; here the advisor call is decided **up front at triage**, because a mid-task escalation to Fable pays twice for the same reasoning.