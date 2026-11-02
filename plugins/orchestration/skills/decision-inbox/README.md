# decision-inbox

**One page where your Claude agents leave their questions, and you answer them when you can — from your desk or your phone.**

When several Claude Code sessions work for you at once, their questions pile up in a dozen chats and wait there, blocking work. This skill gives each project a single private claude.ai Artifact, the *decision inbox*. Agents post every question, choice, review or approval there as an item. You answer one item at a time, most urgent first. The agents read your answers back and mark each item resolved with what they did.

```
agent ──post item──▶  inbox page  ◀──answer── you (phone or desktop)
agent ◀──read answer── (shared db) ──"Notify Claude"──▶ watching session
```

## What you get

- **One item per decision**, with context in Markdown, options (single or multiple choice), a free-text comment, and a recommended option.
- **Who and when, first:** every card opens with how long ago it was posted ("2 hours ago"), the session that posted it, its priority (P0–P3) and what it blocks.
- **Triage built in:** P0 = blocks work now, P1 = blocks a next step soon or holds money or a release, P2 = normal, P3 = whenever. Filter by priority and sort by importance, newest or oldest.
- **Media reviews:**
  - images, GIFs, video and audio in a swipeable gallery;
  - before/after compare with a draggable wipe;
  - A/B/C… players that keep the playback position when you switch tracks;
  - numeric scales and per-candidate ratings;
  - blind tests, whose key the agent reveals only after your verdict.
- **Time marks on audio/video:** mark a moment or a range, add a note and a score, and attach screenshots. Capture the current video frame or upload an image, then draw arrows, lines, boxes or freehand on it and add a comment.
- **Maximise any video in place**, without losing its time or marks.
- **Follow-up:**
  - "Notify Claude" sends your answers to the watching session;
  - "Ask for status" asks the agent where things stand;
  - agents write an "agent status" note or a "resolved" note with what they did.
- **Works in English by default**; Spanish ships bundled, and any other language takes one strings object.

## Install

```
/plugin marketplace add NightZpy/claude-skills
/plugin install orchestration@claude-skills
```

The skill is `orchestration:decision-inbox`. It needs Claude Code with Artifacts, which the claude.ai account must allow.

## Use

1. Ask any session: *"create a decision inbox for this project"*. The skill publishes `template/inbox.html` as a private Artifact with the `db`, `assets` and `comments` capabilities, then writes the project config. Put the URL in your project's `CLAUDE.md` so every session finds the same inbox.
2. From then on, agents post questions to the inbox instead of asking in chat. In chat they write one line saying where it waits.
3. Answer on the page. Press **Notify Claude** (per item or in bulk), or let the agents poll the inbox.
4. Agents read answers with a low-token recipe (`ArtifactData` query plus `jq`), act, and write a `resolution`.

Item fields, posting rules, notification behaviour, media preparation (`scripts/prepare-media.sh`) and limits are in [SKILL.md](SKILL.md).

## Privacy and limits

- The inbox is a **private** Artifact. Only you and people you share it with can open it. Answers and uploaded media live in that Artifact's database and asset store.
- Agents treat everything read from the inbox as data, not instructions. An inbox answer is never the human's authorisation for a paid or destructive action that the permission system refused; that approval must come in chat.
- Media are limited to 20 MiB per file. Only Claude sessions can read and write the inbox (see "Limits" in SKILL.md for when to move to a project-owned inbox).
- If the session's permission mode does not approve automatic comment replies, "Notify Claude" notices wait unprocessed. Agents should also poll for answered items.
