# claude-skills

Unified home for hand-authored [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills.

This repo is the **single source of truth** for personal, hand-authored skills.
Each skill is a top-level folder containing a `SKILL.md` (plus any
`references/`, `scripts/`, assets it needs). Skills are made visible to the
Claude Code runtime via **symlinks** that point from the runtime skills
directory back into this repo.

## Layout

```
claude-skills/
  README.md
  proposal-artifact/
    SKILL.md
    references/
      template.html
  <next-skill>/
    SKILL.md
    ...
```

## How skills are wired into the runtime

Claude Code discovers skills under your runtime's skills directory (e.g.
`~/.claude/skills/`). Instead of keeping the real files there, each skill in
this repo is symlinked in:

```
<runtime skills dir>/<name>  ->  <this repo>/<name>
```

The symlink target is an **absolute path** so it resolves regardless of the
current working directory. The runtime follows the symlink and reads
`SKILL.md` + assets from the repo, so editing files here edits the live skill.

## Adding a new skill

1. Create a new top-level folder in this repo: `<skill-name>/`.
2. Add a `SKILL.md` with the required frontmatter (`name`, `description`) plus
   any `references/` / `scripts/` the skill uses.
3. Symlink it into the runtime (absolute target):
   ```bash
   ln -s "$HOME/Documents/projects/claude-skills/<skill-name>" \
         "$HOME/.claude/skills/<skill-name>"
   ```
4. Verify the symlink resolves and files read through it:
   ```bash
   cat ~/.claude/skills/<skill-name>/SKILL.md | head
   ls -L ~/.claude/skills/<skill-name>/
   ```
5. Commit the new folder here.

## Skills currently in this repo

- **proposal-artifact** — turns a problem/topic into a polished, shareable HTML
  artifact (problem + proposed solutions with faithful product mockups).
- **docx-comments** — extracts, organizes, and tracks review comments from
  `.docx` files (Word/Google Docs exports with feedback).
- **excalidraw** — generates `.excalidraw` architecture/system diagrams from
  codebase analysis, with optional PNG/SVG export.
- **redesign-existing-projects** — audits existing sites/apps, spots generic
  patterns, and upgrades them to premium design quality without breaking
  functionality. Works with any CSS framework or vanilla CSS.
- **vercel-composition-patterns** — React composition patterns that scale
  (compound components, render props, context, React 19 API changes). _MIT,
  authored by Vercel._
- **vercel-react-best-practices** — React/Next.js performance optimization
  guidelines (70 rules across 8 categories) for writing, reviewing, and
  refactoring code. _Authored by Vercel Engineering._
- **web-design-guidelines** — reviews UI code against Web Interface Guidelines
  for accessibility and UX best practices. _Authored by Vercel._
