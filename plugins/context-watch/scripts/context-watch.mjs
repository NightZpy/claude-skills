#!/usr/bin/env node
// Script for the context-watch plugin. One entry point, four modes:
//   bridge (statusLine)            record the session's real window size and usage; prints a short status
//   post   (PostToolUse)           warn once at WARN %; at LIMIT %, finish what is running and start nothing new
//   prompt (UserPromptSubmit)      past LIMIT, remind the session to hand off instead of taking new work
//   start  (SessionStart, clear)   feed the handoff written before /clear into the new session
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';

// Percent of the model's context window. Defaults follow what long-context studies and other context
// monitors converge on (see README): quality drops well before the window is full.
const WARN_PCT = Number(process.env.CONTEXT_WATCH_WARN_PCT) || 60;
const LIMIT_PCT = Number(process.env.CONTEXT_WATCH_LIMIT_PCT) || 75;
const HANDOFF_MAX_AGE_MS = 24 * 3600 * 1000;
const DIR = path.join(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude'), 'context-watch');

const statePath = sessionId => path.join(DIR, `session-${sessionId}.json`);
// Keyed by folder: /clear starts a new session id, the folder stays the same.
const handoffPath = cwd => path.join(DIR, `handoff-${crypto.createHash('sha1').update(cwd).digest('hex').slice(0, 12)}.md`);

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

// Tokens the last main-thread request sent: fresh input plus cache reads and writes.
function contextTokens(transcriptPath) {
  let fd;
  try { fd = fs.openSync(transcriptPath, 'r'); } catch { return 0; }
  try {
    const size = fs.fstatSync(fd).size;
    const start = Math.max(0, size - (4 << 20));
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
      if (!lines[i].includes('"usage"')) continue;
      let e;
      try { e = JSON.parse(lines[i]); } catch { continue; }
      const u = e.type === 'assistant' && !e.isSidechain && e.message?.usage;
      if (u) return (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
    }
    return 0;
  } finally {
    fs.closeSync(fd);
  }
}

// Window size: what the statusLine bridge saw, else CONTEXT_WATCH_WINDOW, else 200k
// (1M once usage has gone past 200k, since only a 1M window allows that).
function windowSize(state, tokens) {
  return state.window || Number(process.env.CONTEXT_WATCH_WINDOW) || (tokens > 200000 ? 1000000 : 200000);
}

function handoffBrief(file) {
  return `Write the handoff to ${file} (create the folder if needed). A fresh session with zero context must resume `
    + 'from it without the user re-explaining. Short and factual, every claim verifiable. Sections: where we are '
    + '(state, what was delivered, evidence: paths, ids, commits); how to run/verify; decisions the user made this '
    + 'session; what changed and why; open issues; next steps, in order; rules that still hold. Then tell the user, '
    + 'in one line, to run /clear: the handoff is loaded into the new session automatically.';
}

const limitMsg = (pct, file) => `[context-watch] Context is at ${pct}% of the window, past the ${LIMIT_PCT}% limit. `
  + 'Let the work already running finish (do not cut it off), but start nothing new: no new tasks, subtasks or '
  + `executors. When it is done: ${handoffBrief(file)}`;

function emit(event, msg) {
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: event, additionalContext: msg } }));
}

const input = readJson(0, {});
const mode = process.argv[2];
fs.mkdirSync(DIR, { recursive: true });
const state = readJson(statePath(input.session_id), {});
const save = () => fs.writeFileSync(statePath(input.session_id), JSON.stringify(state));

if (mode === 'bridge') {
  const cw = input.context_window || {};
  if (cw.context_window_size && cw.context_window_size !== state.window) {
    state.window = cw.context_window_size;
    save();
  }
  if (cw.used_percentage != null) process.stdout.write(`ctx ${Math.round(cw.used_percentage)}% of ${Math.round(cw.context_window_size / 1000)}k`);
} else if (mode === 'post' || mode === 'prompt') {
  const tokens = contextTokens(input.transcript_path);
  const pct = Math.round((100 * tokens) / windowSize(state, tokens));
  const file = handoffPath(input.cwd);
  if (mode === 'post' && pct >= LIMIT_PCT && state.level !== 'limit') {
    Object.assign(state, { level: 'limit', limitAt: Date.now() });
    save();
    emit('PostToolUse', limitMsg(pct, file));
  } else if (mode === 'post' && pct >= WARN_PCT && !state.level) {
    state.level = 'warn';
    save();
    emit('PostToolUse', `[context-watch] Context is at ${pct}% of the window (warning at ${WARN_PCT}%, limit `
      + `${LIMIT_PCT}%). Every turn now costs more and quality starts to drop. Wrap up the current subtask; do not `
      + `start a large new one in this session. At the next natural stopping point: ${handoffBrief(file)}`);
  } else if (mode === 'prompt' && pct >= LIMIT_PCT) {
    const written = fs.existsSync(file) && fs.statSync(file).mtimeMs >= (state.limitAt || 0);
    emit('UserPromptSubmit', written
      ? `[context-watch] Context is at ${pct}% and the handoff is written. Do not take on new work here: answer briefly and ask the user to run /clear.`
      : limitMsg(pct, file));
  }
} else if (mode === 'start' && input.source === 'clear') {
  const file = handoffPath(input.cwd);
  if (fs.existsSync(file) && Date.now() - fs.statSync(file).mtimeMs < HANDOFF_MAX_AGE_MS) {
    const text = fs.readFileSync(file, 'utf8');
    // Used once: a later /clear in this folder must not bring back a stale handoff.
    fs.renameSync(file, file.replace(/\.md$/, `.used-${Date.now()}.md`));
    emit('SessionStart', `[context-watch] Handoff from the session before /clear. Resume from it; do not ask the user to re-explain.\n\n${text}`);
  }
}
