# S2V-020 - One script makes the Markdown copies, llms.txt and the sitemap

Status: resolved
Blocked by: S2V-019

## Goal

`index.md`, `docs.md`, `llms.txt` and `sitemap.xml` are made from the two pages and cannot disagree with them (ADR-021, SPEC §20).

## Scope

- `scripts/build-site.py` (Python 3 standard library only, run as `python3 -I`): reads the two pages; writes the four generated files into `site/`, or into another folder for the check; holds the file allowlist.
- The HTML to Markdown step handles the elements the pages use (headings, paragraphs, lists, tables, code and `pre`, links, strong, emphasis) and skips `data-md="skip"`, `script`, `style` and `button`.
- `site/robots.txt` by hand: allow all; `Sitemap: https://song2vid.pages.dev/sitemap.xml`.
- `site/_headers`: the content types in SPEC §20.
- `site/404.html`: a small page (noindex, no canonical) that says Song2Vid does not publish a page at that address and links the three pages that exist. Without it, Pages answers every unknown address with the home page and status 200 (found on the live site on 2026-11-22).
- Generate the files and commit them.

## Acceptance Criteria

- Running the script twice gives no change.
- `index.md` and `docs.md` contain every heading, every table and every code block of their pages, and none of the skipped parts; they end with the page's canonical address and updated date.
- `llms.txt` lists the pages that exist, each once, with its description from the page; `sitemap.xml` lists `/` and `/docs/` with `lastmod` equal to each page's date.
- `wrangler pages dev` serves each new file with the type in SPEC §20.
- An unknown address returns 404 under `wrangler pages dev`.
- The file list names every file now in `site/` and nothing else.

## Dependencies

S2V-019.

## Comments

- 2026-11-22 (coordinator): Done. `scripts/build-site.py` makes `index.md`, `docs.md`, `llms.txt` and `sitemap.xml`; a second run changes nothing. The Markdown copies keep every heading, table and code block and leave out the picker, Copy button, dialog and the logo link. `robots.txt` and the content types are in place; under `wrangler pages dev` each new file is served with the type in SPEC §20. The allowlist equals the files in `site/` exactly. One thing the plan missed: the live site answers every unknown address with the home page and status 200 (checked: `/roadmap`, `/nonexistent`), because Pages treats a site with no `404.html` as a single-page app. `site/404.html` fixes it; under `wrangler pages dev` unknown addresses now return 404. SPEC §20 and this ticket now say so.
