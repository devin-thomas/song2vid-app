#!/usr/bin/env python3
"""Checks that the download site is agent-ready (SPEC section 20, ADR-021). Called by scripts/check-site.sh.

    python3 -I scripts/check-site-ready.py SITE_DIR COMMAND_VERSION

Every problem is printed on its own line; the exit status is 1 if there is any. Python 3 standard library only.
"""
import importlib.util
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("build_site", HERE / "build-site.py")
build_site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_site)
BASE = build_site.BASE
PAGES = build_site.PAGES

TYPES = {
    "/agent.md": "text/markdown; charset=utf-8",
    "/index.md": "text/markdown; charset=utf-8",
    "/docs.md": "text/markdown; charset=utf-8",
    "/llms.txt": "text/plain; charset=utf-8",
    "/robots.txt": "text/plain; charset=utf-8",
    "/sitemap.xml": "application/xml; charset=utf-8",
}

problems = []


def problem(text):
    problems.append(text)


class Links(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.canonicals, self.alternates, self.targets, self.times = [], [], [], []
        self._time = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "link" and a.get("rel") == "canonical":
            self.canonicals.append(a.get("href", ""))
        if tag == "link" and a.get("rel") == "alternate" and a.get("type") == "text/markdown":
            self.alternates.append(a.get("href", ""))
        for key in ("href", "src"):
            if key in a and not (tag == "link" and a.get("rel") in ("canonical", "alternate")):
                self.targets.append((tag, a[key]))
        if tag == "time":
            self._time = [a.get("datetime", ""), ""]

    def handle_data(self, data):
        if self._time is not None:
            self._time[1] += data

    def handle_endtag(self, tag):
        if tag == "time" and self._time is not None:
            self.times.append(tuple(self._time))
            self._time = None


def file_for(site, address):
    """The file in site that serves an internal address, or None. A folder address needs its trailing slash."""
    path = address.split("#")[0].split("?")[0]
    if path.startswith(BASE):
        path = path[len(BASE):] or "/"
    if path.endswith("/"):
        candidate = site / path.lstrip("/") / "index.html"
    else:
        candidate = site / path.lstrip("/")
    return candidate if candidate.is_file() else None


def main(site, version):
    site = Path(site)

    # 1. The allowlist: only listed files, and every listed file exists.
    listed = set(build_site.allowlist())
    present = {str(p.relative_to(site)) for p in site.rglob("*") if p.is_file()}
    for extra in sorted(present - listed):
        problem(f"{extra} is in the site folder but not on the publish list in scripts/build-site.py")
    for missing in sorted(listed - present):
        problem(f"{missing} is on the publish list but not in the site folder")

    # 2. The generated files are what a fresh build gives.
    with tempfile.TemporaryDirectory() as out:
        try:
            build_site.build(site, out)
        except Exception as error:  # a page the script cannot read is a problem to show, not a crash
            problem(f"scripts/build-site.py could not build from {site}: {error}")
        else:
            for name in build_site.GENERATED:
                made, kept = Path(out) / name, site / name
                if not kept.is_file() or kept.read_text(encoding="utf-8") != made.read_text(encoding="utf-8"):
                    problem(f"{name} differs from a fresh build. Run: python3 -I scripts/build-site.py")

    # 3. Each page: one canonical link to its own address, the Markdown alternate, a visible date, the facts.
    sitemap = (site / "sitemap.xml").read_text(encoding="utf-8") if (site / "sitemap.xml").is_file() else ""
    lastmods = dict(re.findall(r"<loc>([^<]+)</loc><lastmod>([^<]+)</lastmod>", sitemap))
    for page, address, copy in PAGES:
        source_file = site / page
        if not source_file.is_file():
            continue
        source = source_file.read_text(encoding="utf-8")
        links = Links()
        links.feed(source)
        want = BASE + address
        if links.canonicals != [want]:
            problem(f"{page} must have exactly one canonical link, {want} (found {links.canonicals})")
        if links.alternates != ["/" + copy]:
            problem(f"{page} must link its Markdown copy with rel=alternate to /{copy} (found {links.alternates})")
        if not (site / copy).is_file():
            problem(f"{copy}, the Markdown copy of {page}, is missing")
        if len(links.times) != 1:
            problem(f"{page} must show its updated date in exactly one <time> element (found {len(links.times)})")
        else:
            stamp, shown = links.times[0]
            try:
                when = datetime.strptime(stamp, "%Y-%m-%d")
                if shown.strip() != f"{when.day} {when.strftime('%B %Y')}":
                    problem(f"{page}: the visible date '{shown.strip()}' does not match datetime={stamp}")
            except ValueError:
                problem(f"{page}: <time datetime={stamp!r}> is not a date (YYYY-MM-DD)")
            if lastmods.get(want) != stamp:
                problem(f"{page}: updated date {stamp} differs from the sitemap lastmod {lastmods.get(want)}")
        # Every internal link goes to something that exists, and a folder keeps its trailing slash.
        for tag, target in links.targets:
            if target.startswith("#") or re.match(r"^(mailto:|https?://(?!song2vid\.pages\.dev))", target):
                continue
            if file_for(site, target) is None:
                path = target.split("#")[0]
                hint = " (a folder address needs its trailing slash)" if (site / path.lstrip("/") / "index.html").is_file() else ""
                problem(f"{page}: link {target} does not go to a file in the site{hint}")

    # 4. The facts, as text in the HTML the server sends.
    home = (site / "index.html").read_text(encoding="utf-8") if (site / "index.html").is_file() else ""
    docs = (site / "docs/index.html").read_text(encoding="utf-8") if (site / "docs/index.html").is_file() else ""
    shown_version = re.search(r"Version (\d+\.\d+\.\d+)", home)
    if "Free" not in home:
        problem("index.html does not say that Song2Vid is free")
    if "Requires macOS 14 or later" not in home:
        problem("index.html does not say that Song2Vid requires macOS 14 or later")
    if not shown_version:
        problem("index.html does not show the version as 'Version X.Y.Z'")
    elif shown_version.group(1) != version:
        problem(f"index.html shows version {shown_version.group(1)} but the command says {version}")
    for needle in ("Exit statuses and error codes", "image_not_found"):
        if needle not in docs:
            problem(f"docs/index.html does not contain '{needle}'")

    # 5. sitemap, llms.txt and robots.txt list only what exists, and each page once.
    sitemap_locs = re.findall(r"<loc>([^<]+)</loc>", sitemap)
    for _, address, _ in PAGES:
        if sitemap_locs.count(BASE + address) != 1:
            problem(f"sitemap.xml must list {BASE + address} exactly once")
    llms = (site / "llms.txt").read_text(encoding="utf-8") if (site / "llms.txt").is_file() else ""
    internal = re.findall(r"\]\((" + re.escape(BASE) + r"[^)]*)\)", llms)
    for address in sitemap_locs + internal:
        if file_for(site, address) is None:
            problem(f"{address} is listed in sitemap.xml or llms.txt but is not a file in the site")
    for _, address, _ in PAGES:
        if BASE + address not in internal:
            problem(f"llms.txt does not list {BASE + address}")
    robots = (site / "robots.txt").read_text(encoding="utf-8") if (site / "robots.txt").is_file() else ""
    if f"Sitemap: {BASE}/sitemap.xml" not in robots:
        problem("robots.txt does not point to the sitemap")
    if re.search(r"^\s*Disallow:\s*\S", robots, re.M):
        problem("robots.txt blocks a path; every public page should be readable")

    # 6. Content types and the 404 page.
    headers = (site / "_headers").read_text(encoding="utf-8") if (site / "_headers").is_file() else ""
    for path, kind in TYPES.items():
        match = re.search(r"^" + re.escape(path) + r"\n((?:[ \t]+.*\n?)+)", headers, re.M)
        if not match or f"Content-Type: {kind}".lower() not in match.group(1).lower():
            problem(f"_headers does not serve {path} as {kind}")
    notfound = (site / "404.html").read_text(encoding="utf-8") if (site / "404.html").is_file() else ""
    if "noindex" not in notfound or "canonical" in notfound:
        problem("404.html must exist, carry noindex and have no canonical link")

    for line in problems:
        print(f"check-site: {line}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: check-site-ready.py SITE_DIR COMMAND_VERSION")
    sys.exit(main(sys.argv[1], sys.argv[2]))
