---
name: docx-comments
description: Use when processing .docx files to extract, organize, or track review comments. Triggers on Google Docs exports, Word documents with feedback, or when user mentions "comments in the doc", "review feedback", or "docx".
---

# Extracting Comments from .docx Files

## Overview

Google Docs and Word documents store comments in `word/comments.xml` inside the docx zip archive. Reply threads are identified by overlapping text ranges in `word/document.xml`. This skill extracts, threads, and organizes them.

## When to Use

- User shares a `.docx` file and asks about comments or review feedback
- User mentions "comments in the doc", "review feedback from Google Docs"
- Need to track comment threads across document revisions
- Need to produce a structured summary of reviewer feedback

## Quick Reference

### Automated extraction (preferred)

```bash
# Markdown output
python3 ~/.claude/skills/docx-comments/extract_comments.py <file.docx>

# JSON output (for programmatic use)
python3 ~/.claude/skills/docx-comments/extract_comments.py <file.docx> --json

# Save to file
python3 ~/.claude/skills/docx-comments/extract_comments.py <file.docx> -o comments.md
```

### Manual extraction (if script unavailable)

```bash
# 1. Extract XML from docx (it's a zip)
unzip -o file.docx word/comments.xml word/document.xml -d /tmp/docx_extract

# 2. Parse with python3 xml.etree.ElementTree
#    - comments.xml: w:comment elements with w:author, w:id, w:date attrs
#    - Text in nested w:p > w:r > w:t elements
#    - document.xml: commentRangeStart/End markers link comments to text
```

### Key XML structure

| Element | Location | Purpose |
|---------|----------|---------|
| `w:comment` | comments.xml | Comment with author, id, date |
| `w:p > w:r > w:t` | inside comment | Comment text paragraphs |
| `w:commentRangeStart` | document.xml | Start of highlighted text |
| `w:commentRangeEnd` | document.xml | End of highlighted text |

### Threading logic

Comments are replies when their `commentRangeStart/End` ranges **overlap** in `document.xml`. Sort each thread by `w:date` to get chronological order.

## Output Format

When producing a review comments document:

1. **Thread numbering** — Stable IDs (Thread 1, 2, ...) for cross-referencing across revisions
2. **Per thread** — Referenced text, section of source document, table of comments with author + date
3. **Status** — Open, Resolved, Answered, Waiting for X
4. **Notes** — How the comment relates to the document, what action is needed
5. **Summary table** — Count by status for quick triage

## Tracking Across Revisions

When the user provides an updated docx:

1. Run extraction again
2. Match new comments to existing threads by referenced text overlap
3. Add new replies under their parent thread
4. Flag new threads that weren't in the previous version
5. Update status of threads that received responses

## Common Mistakes

- **Treating all comments as independent** — Google Docs replies share overlapping ranges, not parent IDs. Always check range overlap.
- **Missing the document.xml step** — Without it you get comments but not what text they reference.
- **Assuming commentsExtended.xml exists** — Google Docs exports don't include it. Threading comes from range overlap only.
- **Ignoring reactions** — 👍 and other emoji reactions appear in the XML but outside standard `w:comment` elements.
