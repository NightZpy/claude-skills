---
name: plan-big-execute-small
description: Orchestration mode - run the current task with the "plan big, execute small" pattern inside this session. The session model (Fable/Opus) acts as planner+advisor and dispatches bounded execution steps to cheap subagents (Sonnet default, Haiku for mechanical work), reviewing each result against the plan before proceeding. Use when the user invokes /plan-big-execute-small, says "plan big execute small", "patron planner/executor", or asks to run a big task with cheap executors under big-model supervision. NOT for trivial tasks (one file, one step) - just do those directly.
---

# Plan Big, Execute Small — in-session orchestration

You (the session model: Fable/Opus) are the **planner and advisor**. The cheap subagents are the **executors**. The expensive intelligence goes to planning, reviewing, and course-correcting — never to typing mechanical steps.

## Step 0 — Bootstrap (ALWAYS, before planning)

Bootstrap procedure in ONE single bash block + one question to the user if applicable:

1. **Usage signal** (proxy, doesn't know the plan's real limit): `npx -y ccusage blocks --json` → from the active block extract `totalTokens`, `burnRate.tokensPerMinute`, `projection.totalTokens`. Indicative threshold: >150M tokens in the active block or burn >800k/min = strong signal.
2. **Decide mode**: if there's a strong signal, harness warnings, or the user mentioned their `/usage` → ask via AskUserQuestion: **economy mode** (recommended with strong signal) / **normal mode** / **postpone**. No signal → normal mode without asking. The chosen mode governs the entire run (see "Economy mode" below).
3. **Verify fleets ONCE** (not per step), in the same bash block:
   - Codex: `CODEX=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs | tail -1); node "$CODEX" setup --json` → `ready` + `auth.loggedIn`.
   - cc-delegate: `cc-delegate setup --json` (fallback: `node ~/.claude/plugins/cache/claude-code-delegate/cc-delegate/*/scripts/companion.mjs setup --json`) → `ready` and active providers: the actual shape is `providers.<name>.keyPresent` / `.active` / `.quota` (there is NO field called `configured` nor a list `keys`). Active fleet = some provider with `active:true`. None active → suggest `! cc-delegate-keys` ONCE and continue without it.
4. **Announce the resulting routing** in 1-2 lines (which fleet covers judgment/execution/mechanical/review in this run) and only then write the PLAN.

Dispatch gotchas learned (don't repeat):
- `codex-companion.mjs task --background ...` responds in **plain text** ("Codex Task started ... as task-XXXX"), NOT JSON — extract the id with grep/sed on that text, never with json.load. `setup`/`status` do accept `--json`.
- `setup --json` with `ready:true` does NOT guarantee quota: the first task may fail with "You've hit your usage limit... try again at <date>". That error marks the Codex fleet as DOWN for the entire run (the date is usually weeks away) — don't retry; move to the next in the chain (cc-delegate if it has keys; if not, Claude or ask the user).
- Cheap real-quota check: dispatch a trivial task ("reply OK") and check `status` before sending long briefs, or read the first `status` of the first real step before dispatching the rest.

## Roles

| Role | Who | What they do |
|---|---|---|
| Planner | You (session model) | Specifies the complete task, decomposes it into bounded, verifiable steps |
| Executor | Subagent Claude (`sonnet`/`haiku`) or **Codex** (see table below) | Executes ONE bounded step and reports evidence |
| Advisor/Verifier | You | Reviews each result against the plan, corrects course, synthesizes |

Consistent with the global tiering rule: Sonnet is the workhorse; Haiku only for mechanical; genuinely hard tasks (architecture decision, subtle bug, security) are NOT delegated — you do them inline or with an untagged subagent (inherits the session model).

## Available executors: Claude and Codex

Two executor fleets; choose per step. **Verify Codex once at the start of EXECUTE** (not per step): `node ~/.claude/plugins/cache/openai-codex/codex/<version>/scripts/codex-companion.mjs setup --json` → `ready: true` and `auth.loggedIn: true`. If it's not ready, or a task fails due to quota/limit/`model not supported`, **fall through to the Claude equivalent in the table and continue** — note it in the final report, don't stop or retry in a loop.

| Step type | Codex (if available) | Claude (default/fallback) |
|---|---|---|
| Mechanical (renames, moves, reformat, lookups) | `gpt-5.6-luna` effort `low` (alternative: `spark` = `gpt-5.3-codex-spark`) | `model: 'haiku'` |
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

### Third fleet: Frontier (cheap external models)

When: steps of **pure generation** (boilerplate, tests, mechanical text refactor, diff review, very long context analysis) where the executor doesn't need tools — the model returns text/code and you (or a subagent) apply/verify it.

Check availability once at the start of EXECUTE: `cc-delegate setup --json` → `ready: true` (the PATH shim resolves the latest installed version; fallback if not on PATH: `node ~/.claude/plugins/cache/claude-code-delegate/cc-delegate/*/scripts/companion.mjs setup --json`). `ready: false` with missing keys = fleet configurable but inactive — suggest to the user `! cc-delegate-keys` ONCE and continue without it. If the plugin is not installed or there are no keys, this fleet doesn't exist — continue with Claude/Codex, don't stop.

Routing table:

| Step type | Frontier model | Equivalent |
|---|---|---|
| Boilerplate / cheap bulk | `deepseek` | ~Haiku |
| Codegen / refactor / tests in volume | `qwen` | ~Sonnet (low range) |
| Demanding codegen at best price | `deepseek-pro` | ~Sonnet (flagship DeepSeek, cheaper than glm) |
| Complex agentic refactor in text | `glm` | ~Sonnet 5 |
| 1M context audit / deep reasoning | `kimi` | ~Opus (expensive — only if Claude/Codex can't handle the context) |
| Second opinion / generalist frontier | `grok` | ~Opus/GPT-5.5 (Grok 4.5, 500K ctx) |

Dispatch: `cc-delegate task --background --model <alias> --file <ctx>... "<brief>"` → `jobId` → collect with `status`/`result`. Iterative direction: `task --resume last "<correction>"` resends the full thread to the same model — correct without re-packaging context. The brief must be self-contained and specify the expected output format (full code or unified diff). The output is NOT applied: applying it and verifying it is a separate step (yours or a cheap subagent's).

Rule: frontier NEVER for steps requiring command execution, repo exploration, or decision-making — that's Claude/Codex.

### Economy mode (Claude plan limit near)

When it activates (any of these signals):
1. The harness shows usage limit warnings in the conversation (most reliable signal).
2. The user requests it or shares their `/usage` ("economy mode", "we're at 80% and reset is in 3 days").
3. At the start of a long run, cheap check: `npx -y ccusage blocks --json` (active block: burnRate/projection) — estimates consumption from local transcripts; does NOT know the plan's real limit, use it as a proxy together with what the user says. Claude cannot read the exact `/usage` numbers by itself.

Substitution rule while active (goal: the plan Claude lasts until reset):

| Normal role | In economy mode |
|---|---|
| Fable/Opus orchestrates | Continues, but as **minimal supervisor**: plans once, reviews distilled evidence, short verdicts. NEVER reads raw material nor executes steps. |
| Deep judgment that Fable would do inline (design analysis, diagnosis on provided material, audits, resolving ambiguous specs) | Codex `gpt-5.6-terra` (closest available to Fable; Sol gives 400 with ChatGPT auth) → without Codex: `kimi` via cc-delegate (AA 57 ≥ Opus 4.8, the closest substitute; expensive and slow — only for judgment steps, not volume) with ALL the material in `--file`. Fable only issues the final verdict on the response. |
| Sonnet standard execution | Codex `gpt-5.6-terra` (if quota available) → if the step is pure generation, `glm`/`qwen` via cc-delegate |
| Haiku mechanical | Codex `luna`; if pure text transformation, `deepseek` via cc-delegate |
| Review | Codex first (global rule); without Codex → `glm` + second opinion `grok` via cc-delegate; Claude review ONLY for security-critical paths |
| Scouts/research reads | If reading/summarizing textual material: `kimi`/`glm` with `--file`. Claude subagent only when repo tools are needed. |

- Steps that require tools (explore repo, run tests, edit in tree) cannot go to cc-delegate (text-only): they go to Codex; Sonnet remains the last option.
- Deactivate when the reset passes or when the user indicates; note in the final report what ran in economy mode.

## Flow

### 1. PLAN (you, without delegating)
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
- Second failure, or the step turned out to be judgment-heavy → escalate: do it yourself inline or redispatch without a model tag.
- One result may invalidate later steps in the plan — adjust the plan before continuing to dispatch, not after.

### 4. VERIFY & SYNTHESIZE (you)
- Run global verification (tests, build, end-to-end flow — skill `verify` if applicable).
- Final summary for the user: what was done, evidence, what was left out.

## Hard rules

- Never dispatch without a written plan: steps without verification criteria produce false "done ✅" reports.
- Never accept a report without verifiable evidence.
- Escalating is cheap, reworking is expensive: on the second failure of an executor, upgrade the model or do it yourself.
- Trivial tasks (one file, one step) do NOT use this pattern — do them directly; the orchestration overhead outweighs the savings.

## Pattern economics (from the cookbook, measured)

- **The savings come from keeping raw material out of YOUR context.** Heavy tokens (web pages, logs, large files, codebase sweeps) should be read in the subagent's context, which returns distilled findings. If raw material ends up in the coordinator's context, you paid for orchestration for nothing. In cookbook runs: ~2.5x cheaper and ~3x faster, with 84-98% of input billed at worker rate.
- **Delegation has a fixed cost per subagent** — brief granularity has an optimum. Splitting the same work into more, narrower briefs INCREASES cost. Prefer few substantial steps to many micro-steps.
- **Don't delegate judgment on subtle raw material**: a cheap reader can summarize and miss exactly what mattered (fine document analysis, nuance decisions). You read that yourself.
- **Verify the premise too, not just the steps**: if the plan decomposition starts from your memory (a list, an assumption), spend a cheap step verifying it — the cookbook audited 20 facts perfectly against a list that had one wrong item from memory.

## Origin

Adaptation to the Claude Code harness of the CMA cookbook "Plan Big, Execute Small" (tool-less frontier coordinator + cheap workers with tools, reading in parallel threads and reporting distilled findings) and the API advisor tool. Cookbook: https://github.com/anthropics/claude-cookbooks/blob/main/managed_agents/CMA_plan_big_execute_small.ipynb