#!/usr/bin/env python3
"""Check the App Store listing in fastlane/metadata before uploading it.

    python3 tools/check-listing.py

For every language folder it checks Apple's limits (name and subtitle 30,
keywords 100, promotional text 170, description and What's New 4000 characters),
that keywords are comma-separated with no spaces and no repeats, and that no
keyword repeats a word already in that language's name or subtitle (Apple
indexes those already, so a repeat wastes characters). It also flags
em-dashes and en-dashes in the copy (house style), and prints how each
keyword field is used. Exits non-zero on any error. Standard library only.
"""
import pathlib
import re
import sys

META = pathlib.Path(__file__).resolve().parent.parent / "fastlane" / "metadata"
LIMITS = {"name.txt": 30, "subtitle.txt": 30, "keywords.txt": 100,
          "promotional_text.txt": 170, "description.txt": 4000, "release_notes.txt": 4000}
COPY = ["name.txt", "subtitle.txt", "promotional_text.txt", "description.txt", "release_notes.txt"]

errors, warnings = [], []


def words(text):
    return {w for w in re.findall(r"[^\W\d_]+", text.lower())}


def same_word(a, b):
    # Treat simple plurals as the same word (detail/details, facade/facades).
    return a == b or a + "s" == b or b + "s" == a or a + "es" == b or b + "es" == a


for loc in sorted(p for p in META.iterdir() if p.is_dir() and not p.name.startswith(".")):
    def read(name):
        f = loc / name
        return f.read_text(encoding="utf-8").strip() if f.exists() else None

    for name, limit in LIMITS.items():
        text = read(name)
        if text is None:
            continue
        if len(text) > limit:
            errors.append(f"{loc.name}/{name}: {len(text)} characters, limit {limit}")
    for name in COPY:
        text = read(name)
        if text and re.search("[–—]", text):
            warnings.append(f"{loc.name}/{name}: contains an em-dash or en-dash (house style)")
        if text and "TODO" in text:
            errors.append(f"{loc.name}/{name}: contains TODO")

    kw = read("keywords.txt")
    if kw is None:
        continue
    if " " in kw:
        errors.append(f"{loc.name}/keywords.txt: spaces (use commas only)")
    terms = [t for t in kw.split(",") if t]
    dupes = {t for t in terms if terms.count(t) > 1}
    if dupes:
        errors.append(f"{loc.name}/keywords.txt: repeated {sorted(dupes)}")
    title_words = words((read("name.txt") or "") + " " + (read("subtitle.txt") or ""))
    for t in terms:
        clash = [w for w in words(t) if any(same_word(w, n) for n in title_words)]
        if clash:
            errors.append(f"{loc.name}/keywords.txt: '{t}' repeats {clash} from the name or subtitle")
    print(f"{loc.name:6} keywords {len(kw):3}/100  {len(terms)} terms   "
          f"name {len(read('name.txt') or '')}/30  subtitle {len(read('subtitle.txt') or '')}/30")

# The Australian and UK App Stores index both en-AU and en-GB, so a word in both
# is wasted in one of them.
au, gb = META / "en-AU" / "keywords.txt", META / "en-GB" / "keywords.txt"
if au.exists() and gb.exists():
    both = set(au.read_text().strip().split(",")) & set(gb.read_text().strip().split(","))
    if both:
        warnings.append(f"en-AU and en-GB share keywords {sorted(both)} (the AU and UK stores read both)")

for w in warnings:
    print("warning:", w)
for e in errors:
    print("ERROR:", e)
if errors:
    sys.exit(1)
print("Listing OK.")
