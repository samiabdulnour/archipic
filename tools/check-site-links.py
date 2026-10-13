#!/usr/bin/env python3
"""Check every link and asset on the website before it deploys.

Merging to main publishes docs/ to archipic.app, so run this first:

    python3 tools/check-site-links.py

It reads every docs/*.html page, then:
  - local links and files (href/src/content="...png") must exist in docs/,
  - #anchors must match an id on the target page,
  - external http(s) links must answer with a 2xx or 3xx status (after redirects).
Exits non-zero if anything is broken. Standard library plus curl.
"""
import html.parser
import pathlib
import subprocess
import sys
import urllib.parse

DOCS = pathlib.Path(__file__).resolve().parent.parent / "docs"
SITE = "https://archipic.app"


class Links(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs, self.ids = [], set()

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        for key in ("href", "src"):
            if a.get(key):
                self.refs.append(a[key])
        # og:image and similar meta tags point at files on this site.
        if tag == "meta" and (a.get("content") or "").startswith(SITE + "/"):
            self.refs.append(a["content"])


def parse(page):
    p = Links()
    p.feed(page.read_text(encoding="utf-8"))
    return p


pages = {p.name: parse(p) for p in sorted(DOCS.glob("*.html"))}
problems, external = [], set()

for name, page in pages.items():
    for ref in page.refs:
        if ref.startswith("mailto:"):
            continue
        if ref.startswith(SITE):                       # our own absolute URLs
            ref = ref[len(SITE):] or "/"
        if ref.startswith(("http://", "https://")):
            external.add(ref)
            continue
        path, _, frag = ref.partition("#")
        path = urllib.parse.unquote(path.split("?")[0])
        if path in ("", "/"):
            target = name if path == "" else "index.html"
        else:
            target = path.lstrip("/")
        if not (DOCS / target).exists():
            problems.append(f"{name}: missing file {ref}")
        elif frag and target in pages and frag not in pages[target].ids:
            problems.append(f"{name}: no #{frag} on {target}")

for url in sorted(external):
    # curl (built into macOS) rather than urllib: it copes with IPv6/IPv4
    # fallback, where urllib can hang for minutes on some networks.
    r = subprocess.run(["curl", "-s", "-L", "-o", "/dev/null", "--max-time", "20",
                        "-A", "archipic-link-check", "-w", "%{http_code}", url],
                       capture_output=True, text=True)
    status = int(r.stdout or 0)
    if r.returncode != 0 or not 200 <= status < 400:
        problems.append(f"external {url}: HTTP {status} (curl exit {r.returncode})")
    else:
        print(f"ok  {status}  {url}")

print(f"Checked {len(pages)} pages, {len(external)} external links.")
if problems:
    print("\n".join(problems))
    sys.exit(1)
print("All links fine.")
