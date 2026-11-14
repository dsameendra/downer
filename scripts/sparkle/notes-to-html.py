#!/usr/bin/env python3
"""Minimal Markdown to HTML for Sparkle release notes (reads a file, writes HTML to stdout).

Supports what docs/release-notes/<version>.md uses: ## / ### headings, "- " bullets, paragraphs,
**bold**, `code` and [text](https://...) links. Everything else is escaped, never passed through, so
the output is safe to wrap in CDATA.
"""
import html
import re
import sys


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(
        r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
        lambda m: '<a href="%s">%s</a>' % (m.group(2).replace('"', "%22"), m.group(1)),
        text,
    )
    return text


def convert(markdown: str) -> str:
    out, in_list, para = [], False, []

    def flush_para():
        if para:
            out.append("<p>%s</p>" % inline(" ".join(para)))
            para.clear()

    def close_list():
        nonlocal in_list
        if in_list:
            out.append("</ul>")
            in_list = False

    for raw in markdown.splitlines():
        line = raw.rstrip()
        heading = re.match(r"^(#{1,3})\s+(.*)$", line)
        bullet = re.match(r"^[-*]\s+(.*)$", line)
        if heading:
            flush_para()
            close_list()
            level = len(heading.group(1)) + 1  # Sparkle's window already has the app name: start at h2
            out.append("<h%d>%s</h%d>" % (level, inline(heading.group(2)), level))
        elif bullet:
            flush_para()
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append("<li>%s</li>" % inline(bullet.group(1)))
        elif not line.strip():
            flush_para()
            close_list()
        else:
            close_list()
            para.append(line.strip())
    flush_para()
    close_list()
    return "\n".join(out)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: notes-to-html.py <notes.md>")
    with open(sys.argv[1], encoding="utf-8") as f:
        sys.stdout.write(convert(f.read()) + "\n")
