#!/usr/bin/env python3
"""Builds archipic-icon-study.html: current SF Symbols vs the proposed outline sets."""
import base64, io, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SF = os.path.join(HERE, "sf")            # renders of the current icons; not committed
OUT = os.path.join(HERE, "out", "archipic-icon-study.html")

# ---------------------------------------------------------------- geometry
# ("c", d) heavy line · ("b", d) light line · ("bm", d) light line clipped to the
# material swatch · ("d", d) filled dots · ("raw", svg) anything else.
FRAME = "M3.5 3.5H20.5V20.5H3.5Z"
HATCH = ("M-21 24L3 0M-18 24L6 0M-15 24L9 0M-12 24L12 0M-9 24L15 0M-6 24L18 0M-3 24L21 0"
         "M0 24L24 0M3 24L27 0M6 24L30 0M9 24L33 0M12 24L36 0M15 24L39 0M18 24L42 0M21 24L45 0")

# A sparser hatch drawn with the light pen and always visible, for the simplified cut bars.
HATCH4 = ("M-22 24L2 0M-18 24L6 0M-14 24L10 0M-10 24L14 0M-6 24L18 0M-2 24L22 0M2 24L26 0"
          "M6 24L30 0M10 24L34 0M14 24L38 0M18 24L42 0M22 24L46 0")

def dots(pts, r):
    return "".join(f"M{x-r:.2f} {y}a{r} {r} 0 1 0 {2*r} 0a{r} {r} 0 1 0 {-2*r} 0" for x, y in pts)

def squares(pts, h):
    return "".join(f"M{x-h} {y-h}h{2*h}v{2*h}h{-2*h}z" for x, y in pts)

# Simplified at the owner's request (rev D): one idea per icon, nothing else.
WALL  = {"hclip": "M8.5 3H15.5V21H8.5Z", "els": [("c", "M8.5 3H15.5V21H8.5Z")]}   # a cut wall: tall hatched bar
SLAB  = {"hclip": "M3 9H21V15H3Z",       "els": [("c", "M3 9H21V15H3Z")]}         # a cut slab: flat hatched bar
STAIR = {"els": [("c", "M3 19.5H7.5V15H12V10.5H16.5V6H21")]}                      # the steps, and only the steps
DOOR  = {"els": [("b", "M8.41 7.17A11 11 0 0 1 17.33 16.09"),                     # leaf, swing, and the wall it opens in
                 ("c", "M3 18H6.5M17.5 18H21M6.5 18V7")]}

ICONS = {
  # ---- elements, SECTION set (rev B)
  "s-wall": WALL,
  "s-column": {"els": [("a", "M12 1.5V20"), ("b", "M4 21.25H20"),
                       ("c", "M7.5 3.5H16.5M7.5 18H16.5M10 3.5V18M14 3.5V18")]},
  "s-beam":   {"clip": "M4 4.5H20V8H14.25V16H20V19.5H4V16H9.75V8H4Z",
               "els": [("a", "M12 2V22"), ("c", "M4 4.5H20V8H14.25V16H20V19.5H4V16H9.75V8H4Z")]},
  "s-slab": SLAB,
  "s-stair": STAIR,
  "s-door": DOOR,
  "s-window": {"els": [("b", "M12 3.5V20.5M5 9.5H19"), ("c", "M5 3.5H19V20.5H5ZM3.25 20.5H20.75")]},
  "s-roof":   {"clip": "M2.5 13.5L12 4L21.5 13.5H16.6L12 8.9L7.4 13.5Z",
               "els": [("b", "M6.5 15.75V20.75M17.5 15.75V20.75"),
                       ("c", "M2.5 13.5L12 4L21.5 13.5H16.6L12 8.9L7.4 13.5Z")]},

  # ---- elements, PLAN set (new): everything as it appears on a floor plan
  "p-wall": WALL,
  "p-column": {"clip": "M8.5 8.5H15.5V15.5H8.5Z",
               "els": [("b", "M12 2.5V6M12 18V21.5M2.5 12H6M18 12H21.5"), ("c", "M8.5 8.5H15.5V15.5H8.5Z")]},
  "p-beam":   {"clip": "M3 9.5H7.5V14.5H3ZM16.5 9.5H21V14.5H16.5Z",
               "els": [("raw", '<path class="b" stroke-dasharray="1.6 1.9" d="M9.2 10.6H15M9.2 13.4H15"/>'),
                       ("c", "M3 9.5H7.5V14.5H3ZM16.5 9.5H21V14.5H16.5Z")]},
  "p-slab": SLAB,
  "p-stair": STAIR,
  "p-door": DOOR,
  "p-window": {"clip": "M2.75 9H7.5V15H2.75ZM16.5 9H21.25V15H16.5Z",
               "els": [("b", "M7.5 9H16.5M7.5 12H16.5M7.5 15H16.5"),
                       ("c", "M2.75 9H7.5V15H2.75M21.25 9H16.5V15H21.25")]},
  "p-roof":   {"els": [("b", "M8.25 4V15.5H20.5M13 11L8.25 15.5L3.5 20"),
                       ("c", "M3.5 4H13V11H20.5V20H3.5Z")]},

  # ---- materials: one hatch swatch each, the way a drawing legend shows them
  "m-concrete": {"els": [("d", dots([(7,7.4),(11.6,6.4),(16.4,8.2),(8.6,11.6),(17.2,13.2),(6.6,15.6),(11.2,17),(15.6,17.4)], .62)
                               + "M12.4 12.6l2.2 0l-1.1-2zM8.6 9.4l1.7 0l-.85-1.5zM14.6 15.4l1.6 0l-.8-1.4z"), ("c", FRAME)]},
  "m-brick":    {"els": [("bm", "M3.5 7.75H20.5M3.5 12H20.5M3.5 16.25H20.5M9 3.5V7.75M15 3.5V7.75M6 7.75V12M12 7.75V12M18 7.75V12"
                                "M9 12V16.25M15 12V16.25M6 16.25V20.5M12 16.25V20.5M18 16.25V20.5"), ("c", FRAME)]},
  "m-stone":    {"els": [("bm", "M3.5 9.5L8 8.5L12.5 10L17 8.5L20.5 9.8M3.5 15L9 14L13 15.5L20.5 14.2M8 8.5L7 3.5M17 8.5L17.8 3.5"
                                "M12.5 10L13 15.5M6 9L5.4 14.6M9 14L8.2 20.5M16.5 14.9L17 20.5"), ("c", FRAME)]},
  "m-timber":   {"els": [("bm", "M3.5 7C8 5 12.5 9 20.5 6.5M3.5 11C8 9 12.5 12.5 20.5 10.2M3.5 15.2C7 14 9.5 13.6 11 15.2"
                                "M16 15.2C17.5 13.8 19 14 20.5 14.6M3.5 18.6C9 17.6 14 19.2 20.5 17.8"),
                         ("raw", '<ellipse class="b" cx="13.5" cy="15.2" rx="2" ry="1.1"/>'), ("c", FRAME)]},
  "m-metal":    {"els": [("bm", "M-14 24L10 0M-11 24L13 0M-6 24L18 0M-3 24L21 0M2 24L26 0M5 24L29 0M10 24L34 0M13 24L37 0"),
                         ("c", FRAME)]},
  "m-glass":    {"els": [("b", "M7 12.5L12.5 7M7 17L17 7M11.5 17L17 11.5"), ("c", FRAME)]},
  "m-plaster":  {"els": [("d", dots([(6.3,6.3),(10.1,6.3),(13.9,6.3),(17.7,6.3),(8.2,10.1),(12,10.1),(15.8,10.1),
                                      (6.3,13.9),(10.1,13.9),(13.9,13.9),(17.7,13.9),(8.2,17.7),(12,17.7),(15.8,17.7)], .5)),
                         ("c", FRAME)]},
  "m-tile":     {"els": [("b", "M9.17 3.5V20.5M14.83 3.5V20.5M3.5 9.17H20.5M3.5 14.83H20.5"), ("c", FRAME)]},
  "m-fabric":   {"els": [("bm", "M-15 24L9 0M-10 24L14 0M-5 24L19 0M0 24L24 0M5 24L29 0M10 24L34 0M15 24L39 0"
                                "M-15 0L9 24M-10 0L14 24M-5 0L19 24M0 0L24 24M5 0L29 24M10 0L34 24M15 0L39 24"), ("c", FRAME)]},
  "m-other":    {"els": [("d", dots([(8,12),(12,12),(16,12)], .95)), ("c", FRAME)]},

  # ---- rooms (rev D): recognisable objects, like the icons they replace, in the outline style.
  # Furniture-in-plan was tried in rev C and did not read; the owner preferred the old pictograms.
  "r-outdoor":   {"els": [("b", "M4 20.75H20"),
                          ("raw", '<circle class="c" cx="12" cy="9.5" r="6"/>'), ("c", "M12 15.5V20.5")]},
  "r-lobby":     {"els": [("b", "M12 4V20.5M10.2 11.5V14M13.8 11.5V14M3 20.5H21"), ("c", "M4.5 20.5V4H19.5V20.5")]},
  "r-hall":      {"els": [("b", "M8.5 20.5V11A3.5 3.5 0 0 1 15.5 11V20.5M3 20.5H21"),
                          ("c", "M5 20.5V10A7 7 0 0 1 19 10V20.5")]},
  "r-living":    {"els": [("b", "M6 14.5H18M5.5 18.5V20.5M18.5 18.5V20.5"),
                          ("c", "M3 18.5V12.5A1.5 1.5 0 0 1 6 12.5V8A1.5 1.5 0 0 1 7.5 6.5H16.5A1.5 1.5 0 0 1 18 8V12.5A1.5 1.5 0 0 1 21 12.5V18.5Z")]},
  "r-bedroom":   {"els": [("raw", '<rect class="b" x="5.75" y="8.75" width="5.5" height="3.25" rx="1.4"/>'),
                          ("c", "M3.5 5.5V20.5M3.5 17.5H20.5V20.5M3.5 12.5H17A3.5 3.5 0 0 1 20.5 16V17.5")]},
  "r-workspace": {"els": [("b", "M8.5 9H15.5M8.5 12H13"), ("c", "M5.5 5.5H18.5V15.5H5.5ZM2.75 18.75H21.25")]},
  "r-kitchen":   {"els": [("b", "M6.5 8.25H17.5M11 5.75H13"),
                          ("c", "M5 10.5H19V17A3 3 0 0 1 16 20H8A3 3 0 0 1 5 17ZM5 13H3M19 13H21")]},
  "r-bathroom":  {"els": [("b", "M7.5 19V21M16.5 19V21M6 11V6.5A2 2 0 0 1 10 6.5"),
                          ("c", "M3 11H21V14A5 5 0 0 1 16 19H8A5 5 0 0 1 3 14Z")]},
  "r-dining":    {"els": [("c", "M5.5 3.5V8A2.5 2.5 0 0 0 10.5 8V3.5M8 3.5V20.5M16 20.5V3.5C19 5 19.5 9 19 12.5H16")]},
  "r-meeting":   {"els": [("raw", '<circle class="b" cx="5" cy="10.5" r="2"/><circle class="b" cx="19" cy="10.5" r="2"/>'),
                          ("b", "M2.5 18.5A3.5 3.5 0 0 1 5.5 14.9M21.5 18.5A3.5 3.5 0 0 0 18.5 14.9"),
                          ("raw", '<circle class="c" cx="12" cy="8" r="2.75"/>'),
                          ("c", "M6.5 20V18.5A5.5 5.5 0 0 1 17.5 18.5V20")]},
  "r-auditorium":{"els": [("b", "M6 15.5V19.5M12 15.5V19.5M18 15.5V19.5"),
                          ("c", "M3.5 15.5V9A2.5 2.5 0 0 1 8.5 9V15.5M9.5 15.5V9A2.5 2.5 0 0 1 14.5 9V15.5"
                                "M15.5 15.5V9A2.5 2.5 0 0 1 20.5 9V15.5M2.75 15.5H21.25")]},
  "r-library":   {"els": [("b", "M3.5 8.5H7M10.5 8.5H14"),
                          ("c", "M3.5 5H7V19.5H3.5ZM7 7.5H10.5V19.5H7ZM10.5 5H14V19.5H10.5ZM14.6 19.5L17.1 6.5H20.5L18 19.5Z")]},
  "r-shop":      {"els": [("b", "M8 5L7.4 10.5M12 5V10.5M16 5L16.6 10.5M13.5 20.5V14H17V20.5M7 13.5H11V17.5H7Z"),
                          ("c", "M3.5 5H20.5L21.5 10.5H2.5ZM4.5 10.5V20.5H19.5V10.5")]},
  "r-showroom":  {"els": [("b", "M7.5 14.5V4H16.5V14.5"),
                          ("c", "M12 6.5L14.5 9.5L12 12.5L9.5 9.5ZM6 14.5H18V20.5H6Z")]},
  "r-bar":       {"els": [("b", "M7.4 8H16.6"), ("c", "M4.5 5H19.5L12 13ZM12 13V20M8 20.25H16")]},
  "r-spa":       {"els": [("b", "M4 20.5c1.6-1.3 3.2 1.3 4.8 0s3.2-1.3 4.8 0s3.2 1.3 4.8 0"),
                          ("c", "M12 3.5C12 3.5 6.5 9 6.5 12.5A5.5 5.5 0 0 0 17.5 12.5C17.5 9 12 3.5 12 3.5Z")]},
  "r-lab":       {"els": [("b", "M7.4 15.5H16.6"), ("d", dots([(10.5,18)], .6) + dots([(13.3,17.5)], .5)),
                          ("c", "M9.5 3.5H14.5M10.5 3.5V9.5L5 19A1.2 1.2 0 0 0 6 20.75H18A1.2 1.2 0 0 0 19 19L13.5 9.5V3.5")]},
  "r-mechanical":{"els": [("b", "M12 12C10 9 10.5 5.8 12 5.2C13.5 5.8 14 9 12 12M12 12C15.6 11.77 18.12 13.8 17.89 15.4C16.62 16.4 13.6 15.23 12 12"
                                "M12 12C10.4 15.23 7.38 16.4 6.11 15.4C5.88 13.8 8.4 11.77 12 12"),
                          ("d", dots([(12,12)], 1.2)), ("raw", '<circle class="c" cx="12" cy="12" r="8.25"/>')]},
  "r-chapel":    {"els": [("b", "M12 2.5V7M10.4 4.1H13.6M10 20.5V16.5A2 2 0 0 1 14 16.5V20.5"),
                          ("c", "M5.5 20.5V12L12 7L18.5 12V20.5Z")]},
  "r-storage":   {"els": [("b", "M10 14H14"), ("c", "M3 6H21V10H3ZM4.5 10V20H19.5V10")]},
  "r-service":   {"els": [("raw", '<circle class="c" cx="6.2" cy="17.8" r="2.3"/>'),
                          ("c", "M7.8 16.2L15.3 8.7M20.35 7.12A3 3 0 1 1 16.88 3.65")]},
  "r-stairs": STAIR,
  "r-atrium":    {"els": [("b", "M7.5 7.25V10.5M12 4V10.5M16.5 7.25V10.5M3 20.5H21M3.75 10.5H20.25"),
                          ("c", "M4.5 20.5V10.5M19.5 20.5V10.5M3 10.5L12 4L21 10.5")]},
  "r-lounge":    {"els": [("b", "M8 14.5H16M7.5 18.5V20.5M16.5 18.5V20.5"),
                          ("c", "M5 18.5V12.5A1.5 1.5 0 0 1 8 12.5V7.5A2 2 0 0 1 10 5.5H14A2 2 0 0 1 16 7.5V12.5A1.5 1.5 0 0 1 19 12.5V18.5Z")]},
  "r-window":    {"els": [("raw", '<circle class="b" cx="12" cy="9" r="1.7"/>'),
                          ("b", "M8.8 17V15.2A3.2 3.2 0 0 1 15.2 15.2V17M5.5 9.5L8 7M3 20.25H21"), ("c", "M3 5H21V17H3Z")]},
  "r-counter":   {"els": [("b", "M2.75 20.5H21.25M5.5 11H10"),
                          ("c", "M3.5 20.5V8H12.5V12H20.5V20.5")]},
  "r-other":     {"els": [("d", dots([(6.5,12),(12,12),(17.5,12)], 1.2))]},
}

def symbol(name, spec):
    out = []
    if "clip" in spec:
        out.append(f'<clipPath id="cp-{name}"><path d="{spec["clip"]}"/></clipPath>')
    if "hclip" in spec:
        out.append(f'<clipPath id="cp-{name}"><path d="{spec["hclip"]}"/></clipPath>')
    out.append(f'<symbol id="i-{name}" viewBox="0 0 24 24">')
    if "hclip" in spec:
        out.append(f'<use href="#hatch4" class="b" clip-path="url(#cp-{name})"/>')
    if "clip" in spec:
        out.append(f'<use href="#hatch" class="x" clip-path="url(#cp-{name})"/>')
    for kind, d in spec["els"]:
        if kind == "raw":  out.append(d)
        elif kind == "bm": out.append(f'<path class="b" clip-path="url(#cp-mat)" d="{d}"/>')
        else:              out.append(f'<path class="{kind}" d="{d}"/>')
    out.append("</symbol>")
    return "".join(out)

SYMBOLS = "\n".join(symbol(n, s) for n, s in ICONS.items())

# ---------------------------------------------------------------- current icons (real renders)
def sf_css():
    rules = []
    if not os.path.isdir(SF):          # no renders yet: the "now" boxes simply stay empty
        return ""
    for f in sorted(os.listdir(SF)):
        if f.startswith("sf-") and f.endswith(".png"):
            b64 = base64.b64encode(open(os.path.join(SF, f), "rb").read()).decode()
            rules.append(f'.{f[:-4]}{{--m:url(data:image/png;base64,{b64})}}')
    return "\n".join(rules)

# ---------------------------------------------------------------- content
ELEMENTS = [("wall","Wall","rectangle.portrait"),("column","Column","building.columns"),("beam","Beam","rectangle"),
            ("slab","Slab","square"),("stair","Stair","stairs"),("door","Door","door.left.hand.closed"),
            ("window","Window","rectangle.split.2x2"),("roof","Roof","triangle")]
ROOMS = [("outdoor","Outdoor"),("lobby","Lobby"),("hall","Hall"),("living","Living"),("bedroom","Bedroom"),
         ("workspace","Workspace"),("kitchen","Kitchen"),("bathroom","Bathroom"),("dining","Dining"),("meeting","Meeting"),
         ("auditorium","Auditorium"),("library","Library"),("shop","Shop"),("showroom","Showroom"),("bar","Bar"),("spa","Spa"),
         ("lab","Lab"),("mechanical","Mechanical"),("chapel","Chapel"),("storage","Storage"),("service","Service"),
         ("stairs","Stairs"),("atrium","Atrium"),("lounge","Lounge"),("window","Window"),("counter","Counter"),("other","Other")]
MATERIALS = [("concrete","Concrete"),("brick","Brick"),("stone","Stone"),("timber","Timber"),("metal","Metal"),
             ("glass","Glass"),("plaster","Plaster"),("tile","Tile"),("fabric","Fabric"),("other","Other")]
RESIDENTIAL = ["outdoor","living","bedroom","kitchen","bathroom","dining","hall","stairs","storage","other"]

def sf(cls, size=""):   return f'<i class="sf {size} sf-{cls}" role="img" aria-label="current icon"></i>'
def ic(name, px):       return f'<svg width="{px}" height="{px}" viewBox="0 0 24 24" aria-hidden="true"><use href="#i-{name}"/></svg>'

matrix_rows = "".join(
    f'<tr><th scope="row">{label}<span>{sym}</span></th>'
    f'<td>{sf(key,"x3")}</td><td>{ic("s-"+key,72)}</td><td>{ic("p-"+key,72)}</td></tr>'
    for key, label, sym in ELEMENTS)

def pair(prefix, key, label):
    return (f'<figure class="pair"><figcaption>{label}</figcaption><div class="two">'
            f'<div class="box">{sf(prefix+"-"+key,"x25")}</div><div class="box new">{ic(prefix+"-"+key,60)}</div></div></figure>')

room_pairs = "".join(pair("r", k, l) for k, l in ROOMS)
mat_pairs  = "".join(pair("m", k, l) for k, l in MATERIALS)

def tiles(items, mode, pressed):
    out = []
    for i, (key, label) in enumerate(items):
        art = sf(key) if mode == "sf" else ic(key, 24)
        out.append(f'<button type="button" class="tile" aria-pressed="{str(i == pressed).lower()}"><span class="art">{art}</span>{label}</button>')
    return "".join(out)

def mock(title, note, items, mode, pressed):
    return (f'<div class="mock"><h3>{title}</h3><div class="tiles" data-tiles>{tiles(items, mode, pressed)}</div>'
            f'<div class="hint">{note}</div></div>')

el = lambda pre: [((pre + k) if pre else k, l) for k, l, _ in ELEMENTS]
res = lambda pre: [(pre + k, dict(ROOMS)[k]) for k in RESIDENTIAL]
mat = lambda pre: [(pre + k, l) for k, l in MATERIALS]
MOCKS = "".join([
    mock("Element", "Now: system symbols", el(""), "sf", 2),
    mock("Element", "Section set", el("s-"), "ic", 2),
    mock("Element", "Plan set", el("p-"), "ic", 2),
    mock("Room", "Now: system symbols", res("r-"), "sf", 1),
    mock("Room", "Proposed: objects in outline", res("r-"), "ic", 1),
    mock("Materiality", "Now: system symbols", mat("m-"), "sf", 0),
    mock("Materiality", "Proposed: hatch swatches", mat("m-"), "ic", 0),
])

TEMPLATE = io.open(os.path.join(HERE, "template.html"), encoding="utf-8").read()
html = (TEMPLATE.replace("__SFCSS__", sf_css()).replace("__HATCH__", HATCH).replace("__HATCH4__", HATCH4).replace("__FRAME__", FRAME)
        .replace("__SYMBOLS__", SYMBOLS).replace("__MATRIX__", matrix_rows)
        .replace("__ROOMS__", room_pairs).replace("__MATERIALS__", mat_pairs).replace("__MOCKS__", MOCKS))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
io.open(OUT, "w", encoding="utf-8").write(html)
print(f"wrote {OUT}  {len(html)//1024} KB  ·  {len(ICONS)} proposed symbols")
