#!/usr/bin/env python3
"""
Extract comments and reply threads from .docx files exported from Google Docs.

Usage:
    python3 extract_comments.py <path-to-docx> [--json] [--output <path>]

Output formats:
    Default: Markdown with threaded comments
    --json:  JSON array for programmatic use
"""

import xml.etree.ElementTree as ET
import zipfile
import re
import json
import argparse
import sys
import os
from collections import defaultdict


NS = {
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    'w14': 'http://schemas.microsoft.com/office/word/2010/wordml',
}


def extract_xml(docx_path, filename):
    """Extract an XML file from the docx zip archive."""
    with zipfile.ZipFile(docx_path, 'r') as z:
        if filename in z.namelist():
            return z.read(filename).decode('utf-8')
    return None


def parse_comments(comments_xml):
    """Parse comments.xml into a list of comment dicts."""
    root = ET.fromstring(comments_xml)
    comments = []

    for comment in root.findall('.//w:comment', NS):
        cid = comment.get(f'{{{NS["w"]}}}id')
        author = comment.get(f'{{{NS["w"]}}}author')
        date = comment.get(f'{{{NS["w"]}}}date')

        texts = []
        for p in comment.findall('.//w:p', NS):
            p_texts = []
            for r in p.findall('.//w:r', NS):
                for t in r.findall('.//w:t', NS):
                    if t.text:
                        p_texts.append(t.text)
            if p_texts:
                texts.append(''.join(p_texts))

        # Extract @mentions from runs with special styling
        mentions = []
        for p in comment.findall('.//w:p', NS):
            for r in p.findall('.//w:r', NS):
                for t in r.findall('.//w:t', NS):
                    if t.text and '@' in t.text:
                        mentions.append(t.text.strip())

        comments.append({
            'id': cid,
            'author': author,
            'date': date,
            'text': '\n'.join(texts),
            'mentions': mentions,
        })

    return comments


def parse_reactions(comments_xml):
    """Parse emoji reactions on comments (Google Docs export format)."""
    reactions = defaultdict(list)
    # Reactions appear as cr:reaction elements in the comments XML
    root = ET.fromstring(comments_xml)
    # Search all namespaces for reaction elements
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if 'reaction' in tag.lower():
            parent = None
            # Walk up to find parent comment
            for comment in root.findall('.//w:comment', NS):
                if elem in comment.iter():
                    parent = comment.get(f'{{{NS["w"]}}}id')
                    break
            if parent:
                reactions[parent].append({
                    'emoji': elem.text or elem.get('emoji', ''),
                    'author': elem.get('author', ''),
                })
    return reactions


def find_referenced_text(document_xml, comments):
    """Find the text each comment references using commentRangeStart/End markers."""
    # Build range positions for each comment ID
    start_pattern = r'w:commentRangeStart[^>]*w:id="(\d+)"'
    end_pattern = r'w:commentRangeEnd[^>]*w:id="(\d+)"'

    starts = {m.group(1): m.start() for m in re.finditer(start_pattern, document_xml)}
    ends = {m.group(1): m.start() for m in re.finditer(end_pattern, document_xml)}

    for c in comments:
        cid = c['id']
        if cid in starts and cid in ends:
            segment = document_xml[starts[cid]:ends[cid]]
            t_texts = re.findall(r'<w:t[^>]*>([^<]+)</w:t>', segment)
            c['ref_text'] = ''.join(t_texts).strip()
            c['range_start'] = starts[cid]
            c['range_end'] = ends[cid]
        else:
            c['ref_text'] = ''
            c['range_start'] = 0
            c['range_end'] = 0

    return comments


def find_threads(comments):
    """Group comments into threads based on overlapping text ranges."""
    threads = []
    used = set()

    # Sort by range_start for consistent ordering
    sorted_comments = sorted(comments, key=lambda c: c.get('range_start', 0))

    for c in sorted_comments:
        if c['id'] in used:
            continue

        thread = [c]
        used.add(c['id'])

        # Find overlapping comments (replies share overlapping ranges)
        for other in sorted_comments:
            if other['id'] in used:
                continue
            # Check if ranges overlap
            if (c['range_start'] <= other['range_start'] < c['range_end'] or
                    other['range_start'] <= c['range_start'] < other['range_end']):
                thread.append(other)
                used.add(other['id'])

        # Sort thread by date
        thread.sort(key=lambda x: x.get('date', ''))
        threads.append(thread)

    # Also add any comments without ranges
    for c in comments:
        if c['id'] not in used:
            threads.append([c])

    return threads


def format_markdown(threads, source_file=None):
    """Format threads as markdown."""
    lines = []
    lines.append('# Document Review Comments')
    lines.append('')

    if source_file:
        lines.append(f'**Source:** `{os.path.basename(source_file)}`')

    authors = set()
    for thread in threads:
        for c in thread:
            authors.add(c['author'])
    if authors:
        lines.append(f'**Reviewers:** {", ".join(sorted(authors))}')
    lines.append('')
    lines.append('---')
    lines.append('')

    for i, thread in enumerate(threads, 1):
        ref_text = thread[0].get('ref_text', '')
        ref_display = ref_text[:150] + '...' if len(ref_text) > 150 else ref_text

        lines.append(f'## Thread {i}')
        lines.append('')
        if ref_display:
            lines.append(f'**Referenced text:** `{ref_display}`')
            lines.append('')

        lines.append('| # | Author | Date | Comment |')
        lines.append('|---|--------|------|---------|')

        for j, c in enumerate(thread):
            prefix = f'{i}.{j + 1}'
            date_short = c['date'][:10] if c['date'] else ''
            text_escaped = c['text'].replace('|', '\\|').replace('\n', ' ')
            lines.append(f'| {prefix} | {c["author"]} | {date_short} | {text_escaped} |')

        lines.append('')
        lines.append(f'**Status:** Open')
        lines.append('')
        lines.append('---')
        lines.append('')

    # Summary table
    lines.append('## Summary')
    lines.append('')
    lines.append(f'| Metric | Count |')
    lines.append(f'|--------|-------|')
    lines.append(f'| Threads | {len(threads)} |')
    total_comments = sum(len(t) for t in threads)
    lines.append(f'| Total comments | {total_comments} |')
    lines.append(f'| Reviewers | {len(authors)} |')

    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Extract comments from .docx files')
    parser.add_argument('docx_path', help='Path to .docx file')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    parser.add_argument('--output', '-o', help='Output file path (default: stdout)')
    args = parser.parse_args()

    if not os.path.exists(args.docx_path):
        print(f'Error: File not found: {args.docx_path}', file=sys.stderr)
        sys.exit(1)

    comments_xml = extract_xml(args.docx_path, 'word/comments.xml')
    if not comments_xml:
        print('No comments found in document.', file=sys.stderr)
        sys.exit(0)

    document_xml = extract_xml(args.docx_path, 'word/document.xml')

    comments = parse_comments(comments_xml)
    if not comments:
        print('No comments found in document.', file=sys.stderr)
        sys.exit(0)

    if document_xml:
        comments = find_referenced_text(document_xml, comments)

    threads = find_threads(comments)

    if args.json:
        output = json.dumps(threads, indent=2, ensure_ascii=False)
    else:
        output = format_markdown(threads, source_file=args.docx_path)

    if args.output:
        with open(args.output, 'w') as f:
            f.write(output)
        print(f'Written to {args.output}', file=sys.stderr)
    else:
        print(output)


if __name__ == '__main__':
    main()
