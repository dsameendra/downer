#!/usr/bin/env python3
"""Validate the static website in docs/: local references exist, images declare alt/width/height, anchors resolve.

Usage: python3 scripts/check-site.py [SITE_DIR]   (default: docs). Exits 1 with a list of problems.
"""
from __future__ import annotations

import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.refs: list[tuple[str, str]] = []  # (kind, value)
        self.ids: set[str] = set()
        self.problems: list[str] = []
        self.has_title = False
        self.has_description = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        a = {k: v or "" for k, v in attrs}
        if "id" in a:
            self.ids.add(a["id"])
        if tag == "title":
            self.has_title = True
        if tag == "meta" and a.get("name") == "description" and a.get("content"):
            self.has_description = True
        if tag == "img":
            for required in ("alt", "width", "height"):
                if required not in a:
                    self.problems.append(f"<img src={a.get('src', '?')}> is missing {required}")
        for key in ("src", "href", "poster"):
            if key in a and a[key]:
                self.refs.append((key, a[key]))
        if "srcset" in a:
            for part in a["srcset"].split(","):
                if part.strip():
                    self.refs.append(("srcset", part.strip().split()[0]))


def local(ref: str) -> str | None:
    parts = urlsplit(ref)
    if parts.scheme or parts.netloc or ref.startswith(("mailto:", "data:", "#", "javascript:")):
        return None
    return unquote(parts.path)


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "docs").resolve()
    problems: list[str] = []
    pages = sorted(root.glob("*.html"))
    if not pages:
        problems.append(f"no HTML pages in {root}")
    for page_path in pages:
        page = Page()
        page.feed(page_path.read_text(encoding="utf-8"))
        problems += [f"{page_path.name}: {p}" for p in page.problems]
        if not page.has_title:
            problems.append(f"{page_path.name}: missing <title>")
        if not page.has_description:
            problems.append(f"{page_path.name}: missing meta description")
        for kind, ref in page.refs:
            if ref.startswith("#"):
                if ref[1:] and ref[1:] not in page.ids:
                    problems.append(f"{page_path.name}: anchor {ref} has no target")
                continue
            path = local(ref)
            if path is None or path == "":
                continue
            target = (root / path.lstrip("/")) if path.startswith("/") else (page_path.parent / path)
            if not target.resolve().exists():
                problems.append(f"{page_path.name}: {kind} {ref} does not exist")
    for name in ("robots.txt", "sitemap.xml", ".nojekyll"):
        if not (root / name).exists():
            problems.append(f"missing {name}")
    for problem in problems:
        print(f"site: {problem}")
    print(f"site check: {len(pages)} page(s), {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
