#!/usr/bin/env python3
"""Makes the generated public files of the download site from its two pages (SPEC section 20, ADR-021).

    python3 -I scripts/build-site.py                  writes site/index.md, site/docs.md, site/llms.txt, site/sitemap.xml
    python3 -I scripts/build-site.py --out DIR        writes them into DIR instead (the check does this and compares)
    python3 -I scripts/build-site.py --site DIR       reads the pages from DIR (the check uses a broken copy to show a failure)
    python3 -I scripts/build-site.py --allowlist      prints every file that may be published, one per line

site/index.html and site/docs/index.html are the source. Never edit the generated files by hand.
Python 3 standard library only.
"""
import argparse
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

BASE = "https://song2vid.pages.dev"
REPO = "https://github.com/devin-thomas/song2vid-app"

# (html file, address, markdown copy, title in llms.txt is the page's own <title>)
PAGES = [
    ("index.html", "/", "index.md"),
    ("docs/index.html", "/docs/", "docs.md"),
]

# Files written by hand, and the files this script writes. Everything else in site/ must be on this list too.
HAND_WRITTEN = [
    "_headers", "404.html", "robots.txt", "agent.md", "handoff.js", "favicon.svg", "logo.svg", "apple-touch-icon.png",
    "brands/LOBE-ICONS-LICENSE.txt", "brands/chatgpt-original.svg", "brands/claude-original.svg",
    "brands/credits.txt", "brands/grok-bot-original.svg", "brands/muse-color.svg", "brands/muse.svg",
    "screenshots/command-frame.webp", "screenshots/command-make.webp", "screenshots/mac-1x1-crop-dark.webp", "screenshots/mac-1x1-crop-light.webp", "screenshots/mac-9x16-fit-dark.webp", "screenshots/mac-9x16-fit-light.webp", "screenshots/mac-main-16x9-fit-dark.webp", "screenshots/mac-main-16x9-fit-light.webp", "screenshots/mac-video-saved-dark.webp", "screenshots/mac-video-saved-light.webp",
]
GENERATED = ["index.md", "docs.md", "llms.txt", "sitemap.xml"]


def allowlist():
    return sorted(set(HAND_WRITTEN + GENERATED + [page for page, _, _ in PAGES]))


class PageFacts(HTMLParser):
    """The title, description, canonical address and updated date of one page."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title = ""
        self.description = ""
        self.canonical = ""
        self.updated = ""
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "title":
            self._in_title = True
        elif tag == "meta" and a.get("name") == "description":
            self.description = a.get("content", "")
        elif tag == "link" and a.get("rel") == "canonical":
            self.canonical = a.get("href", "")
        elif tag == "time" and not self.updated:
            self.updated = a.get("datetime", "")

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._in_title:
            self.title += data


VOID = {"img", "meta", "link", "br", "hr", "input"}
SKIPPED = {"head", "script", "style", "button", "dialog", "noscript", "nav", "footer", "img"}
PARAGRAPHS = {"p", "div", "section", "header", "main", "article"}


class ToMarkdown(HTMLParser):
    """The text of a page's <main> as Markdown. Parts marked data-md="skip" (and a few tags that only matter in a
    browser) are left out."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks = []
        self.buf = []
        self.stack = []
        self.skip_level = None
        self.pre = None
        self.lists = []
        self.list_lines = None
        self.item_prefix = None
        self.link_marks = []
        self.table = None
        self.row = None
        self.header_rows = 0
        self.cell_saved = None
        self.heading = None

    # -- text pieces
    def _text(self):
        return re.sub(r"\s+", " ", "".join(self.buf)).strip()

    def _flush(self):
        text = self._text()
        self.buf = []
        if not text:
            return
        if self.item_prefix is not None:
            self.list_lines.append(self.item_prefix + text)
            self.item_prefix = None
        elif self.heading:
            self.blocks.append("#" * self.heading + " " + text)
            self.heading = None
        else:
            self.blocks.append(text)

    # -- tags
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if self.skip_level is not None:
            if tag not in VOID:
                self.stack.append(tag)
            return
        if tag not in VOID:
            self.stack.append(tag)
        if tag in SKIPPED or a.get("data-md") == "skip":
            self.skip_level = len(self.stack) if tag not in VOID else None
            return
        if tag == "pre":
            self._flush()
            self.pre = []
        elif self.pre is not None:
            return
        elif tag in ("h1", "h2", "h3", "h4"):
            self._flush()
            self.heading = int(tag[1])
        elif tag in PARAGRAPHS:
            self._flush()
        elif tag in ("ul", "ol"):
            self._flush()
            if not self.lists:
                self.list_lines = []
            self.lists.append([tag, 0])
        elif tag == "li":
            self._flush()
            kind = self.lists[-1]
            kind[1] += 1
            marker = "- " if kind[0] == "ul" else f"{kind[1]}. "
            self.item_prefix = "  " * (len(self.lists) - 1) + marker
        elif tag == "table":
            self._flush()
            self.table = []
            self.header_rows = 0
        elif tag == "tr":
            self.row = []
        elif tag in ("td", "th"):
            self.cell_saved = self.buf
            self.buf = []
        elif tag == "code":
            self.buf.append("`")
        elif tag in ("strong", "b"):
            self.buf.append("**")
        elif tag in ("em", "i"):
            self.buf.append("*")
        elif tag == "a":
            self.link_marks.append((len(self.buf), a.get("href", "")))
        elif tag == "br":
            self.buf.append(" ")

    def handle_startendtag(self, tag, attrs):
        if self.skip_level is None and tag == "br":
            self.buf.append(" ")

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        was_skipping = self.skip_level is not None
        while self.stack and self.stack[-1] != tag:
            self.stack.pop()
        level = len(self.stack)
        if self.stack:
            self.stack.pop()
        if was_skipping:
            if level <= self.skip_level:
                self.skip_level = None
            return
        if tag == "pre" and self.pre is not None:
            self.blocks.append("```\n" + "".join(self.pre).strip("\n") + "\n```")
            self.pre = None
        elif self.pre is not None:
            return
        elif tag in ("h1", "h2", "h3", "h4") or tag in PARAGRAPHS or tag == "li":
            self._flush()
        elif tag in ("ul", "ol"):
            self._flush()
            self.lists.pop()
            if not self.lists:
                self.blocks.append("\n".join(self.list_lines))
                self.list_lines = None
        elif tag in ("td", "th"):
            cell = self._text().replace("|", "\\|")
            self.buf = self.cell_saved
            self.row.append(cell)
        elif tag == "tr":
            if self.row is not None:
                self.table.append(self.row)
                self.row = None
        elif tag == "thead":
            self.header_rows = len(self.table)
        elif tag == "table":
            rows = self.table
            head = rows[0]
            lines = ["| " + " | ".join(head) + " |", "| " + " | ".join("---" for _ in head) + " |"]
            lines += ["| " + " | ".join(r) + " |" for r in rows[1:]]
            self.blocks.append("\n".join(lines))
            self.table = None
        elif tag == "code":
            self.buf.append("`")
        elif tag in ("strong", "b"):
            self.buf.append("**")
        elif tag in ("em", "i"):
            self.buf.append("*")
        elif tag == "a" and self.link_marks:
            at, href = self.link_marks.pop()
            if href.startswith("#") or not href:
                return
            target = BASE + href if href.startswith("/") else href
            self.buf.insert(at, "[")
            self.buf.append(f"]({target})")

    def handle_data(self, data):
        if self.skip_level is not None:
            return
        if self.pre is not None:
            self.pre.append(data)
        else:
            self.buf.append(data)


def markdown_for(page_html, facts):
    # Only <main> is the page's content: header text (logo, title) is inside <main> on both pages.
    body = page_html
    start = body.find("<main>")
    end = body.find("</main>")
    if start < 0 or end < 0:
        raise SystemExit("build-site: a page has no <main> element")
    parser = ToMarkdown()
    parser.feed(body[start:end + len("</main>")])
    parser._flush()
    text = "\n\n".join(block for block in parser.blocks if block.strip())
    return (text + f"\n\n---\n\nThis is the Markdown copy of {facts.canonical}. Updated {facts.updated}.\n")


def build(site, out):
    site, out = Path(site), Path(out)
    out.mkdir(parents=True, exist_ok=True)
    facts = {}
    for page, address, copy in PAGES:
        source = (site / page).read_text(encoding="utf-8")
        f = PageFacts()
        f.feed(source)
        facts[page] = f
        (out / copy).write_text(markdown_for(source, f), encoding="utf-8")

    home = facts["index.html"]
    docs = facts["docs/index.html"]
    llms = f"""# Song2Vid

> {home.description} It also has a `song2vid` command for Terminal, scripts and agents.

## Pages

- [{home.title.strip()}]({BASE}/): {home.description}
- [{docs.title.strip()}]({BASE}/docs/): {docs.description}
- [Agent Guide]({BASE}/agent.md): step-by-step instructions for an agent that finds, installs and uses the command

## Markdown copies

- [Download page, Markdown]({BASE}/index.md)
- [Docs page, Markdown]({BASE}/docs.md)

## Source

- [Source code and releases]({REPO})
"""
    (out / "llms.txt").write_text(llms, encoding="utf-8")

    urls = "".join(
        f"  <url><loc>{BASE}{address}</loc><lastmod>{facts[page].updated}</lastmod></url>\n"
        for page, address, _ in PAGES
    )
    sitemap = ('<?xml version="1.0" encoding="UTF-8"?>\n'
               '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + urls + "</urlset>\n")
    (out / "sitemap.xml").write_text(sitemap, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--site", default="site")
    parser.add_argument("--out")
    parser.add_argument("--allowlist", action="store_true")
    args = parser.parse_args()
    if args.allowlist:
        print("\n".join(allowlist()))
        return
    build(args.site, args.out or args.site)
    print(f"build-site: wrote {', '.join(GENERATED)} into {args.out or args.site}")


if __name__ == "__main__":
    sys.exit(main())
