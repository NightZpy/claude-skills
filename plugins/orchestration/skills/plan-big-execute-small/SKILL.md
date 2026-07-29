---
name: plan-big-execute-small
description: Orchestration mode - run the current task with the "plan big, execute small" advisor/executor pattern inside this session. The session model (Opus 5) orchestrates, verifies and approves; bounded execution goes FIRST to Codex (subscription quota, ~zero marginal cost), then to cc-delegate once Codex runs out of quota, with Claude subagents sized by the Claude-usage mode; Fable 5 is consulted up front, as a one-shot advisor, only for decisions that qualify. Use when the user invokes /plan-big-execute-small, says "plan big execute small", "patron planner/executor", "advisor pattern", or asks to run a big task with cheap executors under big-model supervision. NOT for trivial tasks (one file, one step) - just do those directly.
---

# Plan Big, Execute Small — in-session orchestration

You (the session model, **Opus 5**) are the **orchestrator, verifier and approver**, always — in every mode, with every fleet. What changes from run to run is only *who types*. The expensive intelligence goes into specifying, reviewing and course-correcting; never into typing mechanical steps.

The pattern applies **always**, whether or not cheap external fleets are available. Crossing a usage threshold swaps the executor fleet; it never swaps the pattern, and it never moves approval off you.

## Step 0 — Bootstrap (ALWAYS, before planning)

Bootstrap procedure in ONE single bash block + one question to the user if applicable:

1. **Ask the user for the real numbers — that's the only hard threshold there is.** `/usage` renders as an interactive screen: it leaves no stdout, no file, no endpoint you can read. Nothing on disk has them — not `~/.claude/usage.db` (raw tokens only), not `.claude.json` (`lastModelUsage` = cumulative tokens/cost), not the transcripts (no rate-limit headers). **So ask, in one line:**

   > "Run `/usage` and paste me three numbers: session %, time to session reset, and **weekly %** (the one that matters)."

   Ask at Step 0 of any long run, and **again when the run has burned through a chunk of budget** — a plan written under "weekly 40%" is the wrong plan at 85%. Don't re-ask every step; once per major phase is enough. If the user declines or doesn't have them, fall back to the proxy below and say out loud that the mode is a guess.

   **Cuts by weekly % (hard, when you have the number):** <50% → **Claude-led** · 50–75% → **Split** · 75–90% → **Delegate-led** · >90% → **Lifeboat**. Session % is a *separate, temporary* signal: session near 100% with a healthy weekly means lean on Codex/cc-delegate until the reset shown in `projection.remainingMinutes`, not a permanent mode downgrade.

2. **Proxy, only when the user gave you nothing** (it measures consumption, never the limit): `npx -y ccusage blocks --json` → from the active block, `totalTokens`, `burnRate.tokensPerMinute`, `projection.remainingMinutes` (when the 5h block resets — this one IS real). Indicative threshold: >150M tokens in the active block or burn >800k/min = strong signal. It knows **nothing** about your plan's quota or the weekly window, so treat every mode derived from it as provisional. Default **Split**; on a strong signal or harness usage warnings, ask via AskUserQuestion **Delegate-led** (recommended) / **Split** / **Claude-led** / **postpone**. No signal and plenty of budget → **Claude-led** without asking. The chosen mode governs the run until you re-ask.

   **Two thresholds are in play — don't confuse them.** *This* one (your Claude budget, read from `ccusage` + harness warnings) decides **WHEN cc-delegate enters at all**. The plugin's own threshold is a **monthly USD spend quota per provider** (`cc-delegate setup`, default $10 OpenRouter, alerts ⚠ 80% / 🔴 100%) and only caps **HOW MUCH** it may spend once it's in. cc-delegate cannot see your Claude usage — nothing but you crosses the first threshold.
3. **Verify fleets ONCE** (not per step), in the same bash block. **Codex is the first fleet and the one that decides the shape of the run** — check it first:
   - Codex: `CODEX=$(ls -td ~/.claude/plugins/cache/openai-codex/codex/*/ | head -1)scripts/codex-companion.mjs; node "$CODEX" setup --json` → `ready` + `auth.loggedIn`. `ls -td … | head -1` matters: old plugin versions stay in the cache marked `.orphaned_at`.
   - **Which Codex models this account actually has**, same block: `jq -r '.models[]? | "\(.slug) ctx=\(.context_window // "?")"' ~/.codex/models_cache.json` (fallback: `cat ~/.codex/models_cache.json`). Trust that cache over the table below — the model list is served per account and rolls out gradually. Also read `~/.codex/config.toml` (`model`, `model_reasoning_effort`) — that's what a call with no `--model`/`--effort` will use.
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
| Executor | **Codex first** (while it has quota), **cc-delegate** once Codex is out, Claude subagents (`sonnet`/`haiku`) sized by the mode | Executes ONE bounded step and returns evidence |
| Verifier / approver | **You, always** | Checks each result against its criterion, corrects course, synthesizes, approves |

Sonnet is the workhorse executor; Haiku only for genuinely mechanical steps. Judgment (architecture, subtle bugs, security, ambiguous specs) is never handed to an executor: either you do it inline, or — if it meets the bar below — Fable specifies it *before* any code is written.

### Harness mechanics for Claude subagents

Two properties of the `Agent` tool silently break the tiering above if you get them wrong:

- **The 1M-context variant is only obtainable by leaving an agent UNTAGGED**, so it inherits the session model. The subagent enum (`sonnet|opus|haiku|fable`) has no 1M entry, so an explicit `model: 'opus'` yields *standard* context. Untag anything that needs deep reasoning over a lot of material.
- **`CLAUDE_CODE_SUBAGENT_MODEL` must stay `"inherit"` or stay unset** in `settings.json`. A fixed value is the highest-priority override and silently beats the per-call `model` — every tier in this skill collapses to one model, with no error to tell you. Precedence: `CLAUDE_CODE_SUBAGENT_MODEL` (when fixed) > per-call `model` > subagent frontmatter `model` > session model.

## When Fable advises — decided UP FRONT, never after a failure

Fable is the most expensive model available, so it is consulted **once, at triage, before planning** — never as a rescue. "I tried, it failed, now I'll call Fable" pays twice for work Fable would have done once; and if the failure came from missing information, a bigger model doesn't fix it either.

**Call Fable when any of these is true** (evaluate before you plan):
- the decision is **hard to reverse** — architecture, data schema, public contract, migration path;
- **being wrong costs far more than tokens** — security, money, data loss, a public interface others will build on;
- the **solution space is wide and the choice determines everything downstream**;
- there is a **real tension between requirements** that someone must resolve before code exists.

None of them → you plan it yourself. In doubt with a cheap-to-reverse decision → you plan it yourself.

**Codex can take the advisor call too — `gpt-5.6-sol` at `high`/`xhigh`, which costs subscription quota instead of Fable's dollars.** It scores level with Fable on aggregate indices, so make it the default advisor. The exception is the top of the Fable bar: when the decision is genuinely unrecoverable (security, money, data loss, a public contract), pay for Fable — Sol's long-horizon reliability is the one thing nobody has measured cleanly (see the translation table).

**How.** One `Agent` call, `model: 'fable'`, prompt framed as *analyse / specify / identify edge cases* — never "implement". Give it the full problem, ask for a structured spec (numbered decisions, constraints, edge cases, verification criteria). It returns the spec and it's done: **its spec goes straight to the executors as the plan's steps; you don't re-litigate it, you verify the results.** If Fable's spec turns out to be wrong under execution evidence, that's a new triage — bring the evidence back in ONE targeted follow-up, don't start a conversation.

## First fleet: Codex

**Codex is the default executor for every step it can do.** It bills against the ChatGPT subscription, so its marginal cost is ~zero: while it has quota, a step that goes to Codex is a step that costs neither Claude budget nor OpenRouter dollars. Everything else is a fallback for what Codex can't take. Verified once at bootstrap (Step 0); if it isn't ready, or a task fails on quota/limit/`model not supported`, **fall through — cc-delegate first, then Claude** — note it in the final report, don't stop or retry in a loop.

### Codex models — what the runtime actually accepts

The plugin is a **passthrough**: it does not validate or list models (`scripts/codex-companion.mjs`). Whatever string you pass in `--model` goes straight to Codex's app-server, so an invalid or unavailable model fails **late**, as a 400 from OpenAI, not as a local error. Two consequences: the model cache read at Step 0 is your only real catalogue, and a typo costs a round-trip.

- **Only alias:** `spark` → `gpt-5.3-codex-spark`. Every other model must be written in full.
- **Valid efforts:** `none | minimal | low | medium | high | xhigh`. GPT-5.6 also advertises `max`/`ultra` in its own catalogue, but the **wrapper rejects them locally** before they reach Codex — `xhigh` is the practical ceiling.
- **No `--model`/`--effort` → the defaults in `~/.codex/config.toml`.** Pin both explicitly, always: model defaults differ per model (`sol` defaults to `low`, everything else to `medium`) and the config default overrides nothing — that's how a mechanical step silently runs at `xhigh`.

### Translation table — which Codex model replaces which Claude model

You already think in Claude tiers. Translate directly; don't re-derive from benchmarks per step.

| Instead of… | Use | Effort | Evidence, and how much to trust it |
|---|---|---|---|
| **Haiku 4.5** (mechanical) | `gpt-5.4-mini`, or `gpt-5.6-luna` if you want one model for both cheap tiers | `low` | Price parity ($0.75/$4.50 vs $1/$5) and same order of magnitude on aggregate indices. **No shared benchmark — low confidence.** Fine, because mechanical steps are verified by a command anyway |
| **Sonnet 5** (workhorse execution) | `gpt-5.6-luna` (fallback `gpt-5.4`) | `medium` | Terminal-Bench 2.1 official: Luna 75.7%±1.3 vs Sonnet 5 74.6%±1.6 — **overlapping error bars, the solidest row here.** Luna is also ~3× cheaper |
| **Opus 5** (deep execution, verification) | `gpt-5.6-terra` (fallback `gpt-5.5`) | `high` — **not `xhigh`** | TB2.1: Terra 78.4% ≈ **Opus 4.8** (78.9%), below Opus 5. Treat Terra as previous-Opus tier: good enough to execute a hard step, not to replace your own judgment. Terra is **non-monotonic in effort** (on ARC-AGI-2 `xhigh` scored *worse* than `max`) — cap at `high` unless you measure otherwise |
| **Fable 5** (one-shot advisor) | `gpt-5.6-sol` — **verified working under ChatGPT auth, jul-2026** | `high`/`xhigh` — **its default is `low`, always pin it** | Artificial Analysis index: Fable 60 vs Sol 59, both the top of their family. Older `openai/codex` issues report Sol 400ing under ChatGPT auth — no longer true here (CLI 0.146.0), but re-test with a trivial task if it starts failing. **Keep Fable when being wrong is unrecoverable**: METR could not get a robust long-horizon measurement for Sol because of detected eval-gaming, so for a decision you cannot walk back, pay for Fable |

**Context is the hard limit, not quality:** Codex exposes **272K to every model** (`gpt-5.4` alone reports 1M as max). Claude gives you 1M. A step whose material doesn't fit in 272K does not go to Codex — split it, or keep it on a Claude subagent / cc-delegate text mode with `--file`.

Caveats worth remembering before you over-trust the rows: the Claude and OpenAI scores come from **different scaffolds** (Claude Code vs Codex agent), so they mix model with harness; SWE-bench numbers for the 5.6 family are disputed and are deliberately not used above; and nobody has published comparisons on tool use, instruction-following or over-editing. Route on this, then judge by the evidence each step returns.

Other models present in the catalogue: `gpt-5.5` (prev-gen frontier, the deep fallback), `gpt-5.4` (`config.toml` default today, the long-material one), `gpt-5.3-codex-spark`/`spark` (near-instant, text-only, **ChatGPT Pro only**).

**The catalogue is per account and can lag the CLI** — 5.6 needs Codex CLI ≥0.144.0 *and* a refreshed `models_cache.json`. Route on what Step 0 actually read: 5.6 absent → `gpt-5.4-mini`/`gpt-5.4`/`gpt-5.5` are the whole fleet and that's fine. If it should be there and isn't, `npm install -g @openai/codex@latest` refreshes the catalogue.

### Step type → executor

**Classify each step by difficulty, not by the name of the task.** A step is *mechanical* only when **the correct answer is unique and a command proves it** — it compiles, the tests pass, the grep comes back clean — and nothing has to be decided along the way. A rename across 40 call-sites with edge cases is *not* mechanical; it's standard execution. Misclassification is the real cause of "the cheap model wasn't good enough", so when a step's verification fails, suspect the classification before the model. Retrying at the cheap tier costs cents, so cheap steps may retry freely — that asymmetry is exactly why Fable is decided up front and `gpt-5.4-mini` doesn't have to be.

| Step type | Codex (first choice) | If Codex is out of quota | Claude (last resort) |
|---|---|---|---|
| Mechanical (unique answer, command-verifiable) | `gpt-5.4-mini` / `gpt-5.6-luna`, effort `low` | cc-delegate cheap tier, text mode | `model: 'haiku'` |
| Standard execution (implement bounded step) | `gpt-5.6-luna`, effort `medium` | cc-delegate (agentic if the step needs tools) | `model: 'sonnet'` |
| Hard execution / subtle logic | `gpt-5.6-terra` `high` (fallback `gpt-5.5` `high`) | cc-delegate deep tier | `model: 'sonnet'`, or inline you |
| Material over 272K | — **Codex can't take it** | cc-delegate text mode with `--file`/`--diff` | read-only Sonnet scout |
| Review of what was executed | native `review` / `adversarial-review` (see below) | cc-delegate `glm`, `grok` for a second opinion | fresh subagent, security-critical paths only |

### How to dispatch Codex

Let `$CODEX` be the runtime path resolved at Step 0 (`…/codex/<newest>/scripts/codex-companion.mjs`). Every subcommand takes `--cwd/-C <dir>`.

- **Via subagent** (simple, one step): `Agent` with `subagent_type: 'codex:codex-rescue'` and the brief as prompt; the forwarder makes ONE `task` call. Say in the brief whether it writes, and pin the tier: "use `--model gpt-5.4 --effort medium`". Without flags it inherits `config.toml`.
- **Via direct runtime** (to parallelize N Codex steps): `node "$CODEX" task --background --write --model X --effort Y "<brief>"` per step → the reply is **plain text** ("Codex Task started … as task-XXXX"), grep the id, never json-parse it → collect with `node "$CODEX" status <job-id>` / `result <job-id>`. Read-only step: omit `--write` (absence = read-only sandbox; presence = workspace-write).
- **Review steps use the native reviewers**, not a hand-written brief: `node "$CODEX" review [--base <ref>] [--scope auto|working-tree|branch] [--wait|--background]` and `adversarial-review [focus]`. They run Codex's own reviewer harness — that's the default review path, and it satisfies the global "review always with Codex" rule.
- `status` = `failed` → read the error before reacting. Quota (`usage_limit_reached`, 429) → **the Codex fleet is DOWN for the whole run**, move to cc-delegate, don't retry. `model not supported`/400 → drop to a model the Step 0 cache confirmed. Brief cause → fix the brief and retry ONCE.

Mixing rules:
- Codex executes in the real working tree (not in isolated context): **never two writers (Codex, cc-delegate agentic or Claude) on the same files at the same time** — steps that write to different areas can run in parallel; if they share files, sequence them or use worktrees.
- The brief to Codex must be as self-contained as a Claude subagent's, and also explicitly state what evidence to return (Codex doesn't see your plan).

## Second fleet: cc-delegate — the backup when Codex runs out

**cc-delegate takes over from Codex the moment Codex has no quota** (and, independently, absorbs Claude's execution once your Claude budget crosses the threshold — see the modes). It is the fleet that keeps the run alive when the free one dies: it costs real OpenRouter dollars, which is exactly why it goes second and not first.

**For all its specifics — text vs agentic, which model by capability/price, how to write the brief, dispatch, and reading usage/health/advisory signals — invoke the `cc-delegate:using-cc-delegate` skill.** Don't duplicate that logic here; this section only covers how it slots into the orchestration.

Availability (check once at bootstrap, Step 0 already does): `cc-delegate setup --json` → `ready:true` and the additive `agentic:{installed,...}` block. Not installed / no keys → this fleet doesn't exist for the run; suggest `! cc-delegate-keys` ONCE and continue with Codex/Claude, don't stop. **Check it at Step 0 even when Codex looks healthy** — a mid-run quota death is when you need to already know whether the backup exists.

Where it sits vs the other fleets:
- **Text mode** = pure generation with no tools (boilerplate, tests, mechanical refactor of provided code, diff review, long-context reads). Cheapest. Output is NOT applied — you or a cheap subagent apply + verify.
- **Agentic mode** (`task --agentic [--write]`) = the delegate needs to explore the repo, run commands, or edit in place. ~100× a text call but still cheaper than a Claude subagent; use it for tool-requiring bounded steps when Codex is unavailable/out of quota.
- Decisions (design, architecture, security) stay with the orchestrator regardless of fleet.

### Delegation modes (four, driven by the Claude-usage signal)

**Codex sits outside this scale: it's the first choice in every mode, because subscription quota makes it free at the margin.** The modes only decide who covers what Codex doesn't — and that's driven by your Claude budget. Below the threshold that's Claude subagents; above it, cc-delegate absorbs what those subagents would have done; deeper still, it also absorbs judgment, and finally the coordination itself. Independently of the mode, **cc-delegate is also the immediate backup the moment Codex hits its usage limit** — in Claude-led just as much as in Lifeboat.

Sources for the mode, best first: **the `/usage` numbers you asked the user for** (weekly % is the binding one — see Step 0 for the cuts), harness usage-limit warnings, then the `ccusage` proxy. You cannot read `/usage` yourself from any script; if you're routing on the proxy alone, say so instead of implying you know the budget.

| Mode | When | Who executes | You |
|---|---|---|---|
| **Claude-led** | Plenty of budget, far from reset | Codex first; Claude subagents (`sonnet`/`haiku`) for what it can't take. cc-delegate as Codex's backup, plus bulk boilerplate and long reads that would bloat context | do the substantive work yourself; quality-first |
| **Split** *(default)* | Normal | Same order, but every bounded step is delegated: codegen, refactors, tests, diff review, research reads | orchestrate + the genuinely hard thinking |
| **Delegate-led** | Near the limit / harness warnings / user says so | **cc-delegate takes over execution**; judgment steps go out too, with all material in `--file`/`--diff` | minimal supervisor: plan once, read distilled evidence, short verdicts — never read raw material, never execute |
| **Lifeboat** | Effectively out of Claude | `cc-delegate orchestrate` runs the loop: plans, dispatches parallel workers in isolated worktrees, merges only clean patches | plan once, then apply + verify what comes back. It never self-approves |

**Which cc-delegate model** for a given step — invoke the **`cc-delegate:using-cc-delegate` skill**; it is the single source of truth and already maps mode × strategy (TEXT/AGENTIC) to exactly one model, using the same four mode names. Don't re-derive it here.

Substitution order within any mode: **Codex** (the model its cache confirmed — `terra`/`luna` if present, else `gpt-5.4`/`gpt-5.4-mini`, `gpt-5.5` for the hard ones) while it has quota → **cc-delegate** the moment Codex is out → **Claude subagent** (`sonnet`/`haiku`), whose share shrinks as the mode moves right. Review: native Codex `review`/`adversarial-review` first; Codex down → `glm` (+ `grok` for a second opinion) via cc-delegate; a Claude review only for security-critical paths.

Announce the active mode at Step 0; step back down once the reset passes or the user says so; note in the final report what ran delegated vs in-session, and on which fleet.

## Flow

### 1. PLAN (you, without delegating)
- **Triage first, before reading anything expensive:** does this task meet the Fable bar above? Yes → one Fable subagent returns the spec, and **that spec becomes the plan's steps directly** — you don't rewrite it, you verify what the executors produce against it. No → you write the plan.
- Read the minimum necessary to specify well (or dispatch 1-2 read-only Sonnet scouts if the map is large).
- Write the plan: **bounded** steps (one deliverable per step), each with: objective, files/scope, expected output, and **how to verify** (command, test, observable criterion).
- Mark dependencies: independent steps are dispatched in parallel; dependent ones, in sequence.
- Present it to the user in 3-6 lines before executing (unless a plan has already been approved).

### 2. EXECUTE (delegated)
- One executor per step, picked from the step-type table: **Codex first**, cc-delegate if Codex is out of quota, a Claude `Agent` (`sonnet`, or `haiku` if mechanical) for what neither covers. Independent steps → dispatch in parallel in a single message; Codex steps go `--background` so Claude/cc-delegate steps dispatch without waiting.
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