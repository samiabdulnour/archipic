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

def dots(pts, r):
    return "".join(f"M{x-r:.2f} {y}a{r} {r} 0 1 0 {2*r} 0a{r} {r} 0 1 0 {-2*r} 0" for x, y in pts)

def squares(pts, h):
    return "".join(f"M{x-h} {y-h}h{2*h}v{2*h}h{-2*h}z" for x, y in pts)

DOOR = [("b", "M9.18 5.73A10.5 10.5 0 0 1 17.27 13.82"),
        ("c", "M2.75 16H7V20H2.75M21.25 16H17.5V20H21.25M7 16V5.5")]
PSTAIR = [("b", "M6.6 7V17M10.2 7V17M13.8 7V17M17.4 7V17"),
          ("b", "M4.8 12H19M16.9 10L19 12L16.9 14"),
          ("c", "M3 7H21V17H3Z")]

ICONS = {
  # ---- elements, SECTION set (rev B)
  "s-wall":   {"clip": "M9.5 3.5H14.5V18H18V21H6V18H9.5Z",
               "els": [("b", "M3 15H6.5M17.5 15H21"), ("c", "M9.5 3.5H14.5V18H18V21H6V18H9.5Z")]},
  "s-column": {"els": [("a", "M12 1.5V20"), ("b", "M4 21.25H20"),
                       ("c", "M7.5 3.5H16.5M7.5 18H16.5M10 3.5V18M14 3.5V18")]},
  "s-beam":   {"clip": "M4 4.5H20V8H14.25V16H20V19.5H4V16H9.75V8H4Z",
               "els": [("a", "M12 2V22"), ("c", "M4 4.5H20V8H14.25V16H20V19.5H4V16H9.75V8H4Z")]},
  "s-slab":   {"clip": "M3 5.5H21V9H3Z",
               "els": [("b", "M7 11.5V20.75M17 11.5V20.75M3 20.75H21"), ("c", "M3 5.5H21V9H3Z")]},
  "s-stair":  {"clip": "M3.5 20.5V16H8.5V11.5H13.5V7H20.5V10.04L8.88 20.5Z",
               "els": [("b", "M4 11.55L13.78 2.75H21"),
                       ("c", "M3.5 20.5V16H8.5V11.5H13.5V7H20.5V10.04L8.88 20.5Z")]},
  "s-door":   {"clip": "M3 16H7V20H3ZM17.5 16H21V20H17.5Z", "els": DOOR},
  "s-window": {"els": [("b", "M12 3.5V20.5M5 9.5H19"), ("c", "M5 3.5H19V20.5H5ZM3.25 20.5H20.75")]},
  "s-roof":   {"clip": "M2.5 13.5L12 4L21.5 13.5H16.6L12 8.9L7.4 13.5Z",
               "els": [("b", "M6.5 15.75V20.75M17.5 15.75V20.75"),
                       ("c", "M2.5 13.5L12 4L21.5 13.5H16.6L12 8.9L7.4 13.5Z")]},

  # ---- elements, PLAN set (new): everything as it appears on a floor plan
  "p-wall":   {"clip": "M4 4H21.25V8.5H8.5V21.25H4Z",
               "els": [("c", "M21.25 4H4V21.25M21.25 8.5H8.5V21.25")]},
  "p-column": {"clip": "M8.5 8.5H15.5V15.5H8.5Z",
               "els": [("b", "M12 2.5V6M12 18V21.5M2.5 12H6M18 12H21.5"), ("c", "M8.5 8.5H15.5V15.5H8.5Z")]},
  "p-beam":   {"clip": "M3 9.5H7.5V14.5H3ZM16.5 9.5H21V14.5H16.5Z",
               "els": [("raw", '<path class="b" stroke-dasharray="1.6 1.9" d="M9.2 10.6H15M9.2 13.4H15"/>'),
                       ("c", "M3 9.5H7.5V14.5H3ZM16.5 9.5H21V14.5H16.5Z")]},
  "p-slab":   {"els": [("b", "M6 8h2.4v2.4h-2.4zM15.6 8h2.4v2.4h-2.4zM6 13.6h2.4v2.4h-2.4zM15.6 13.6h2.4v2.4h-2.4z"),
                       ("c", "M3.5 5.5H20.5V18.5H3.5Z")]},
  "p-stair":  {"els": PSTAIR},
  "p-door":   {"clip": "M3 16H7V20H3ZM17.5 16H21V20H17.5Z", "els": DOOR},
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

  # ---- rooms: furniture in plan, which is how a drawing says what a room is for
  "r-outdoor":   {"els": [("raw", '<circle class="b" cx="18.2" cy="18.2" r="3"/><circle class="c" cx="10" cy="10" r="6"/>'),
                          ("d", dots([(10,10)], .9) + dots([(18.2,18.2)], .6))]},
  "r-lobby":     {"els": [("b", "M7.76 7.76L16.24 16.24M16.24 7.76L7.76 16.24"),
                          ("raw", '<circle class="c" cx="12" cy="12" r="6"/>'), ("c", "M2.5 12H6M18 12H21.5")]},
  "r-hall":      {"els": [("d", squares([(8,8.7),(12,8.7),(16,8.7),(8,15.3),(12,15.3),(16,15.3)], .8)),
                          ("c", "M3.5 5H20.5V19H3.5Z")]},
  "r-living":    {"els": [("b", "M6.5 12.5V7H17.5V12.5"), ("b", "M8.5 15.5H15.5V19.5H8.5Z"), ("c", "M4 4.5H20V12.5H4Z")]},
  "r-bedroom":   {"els": [("b", "M7 5.5H11V8.5H7ZM13 5.5H17V8.5H13ZM5 11.5H19"), ("c", "M5 3.5H19V20.5H5Z")]},
  "r-workspace": {"els": [("b", "M9 7.75H15"), ("raw", '<circle class="b" cx="12" cy="16" r="2.5"/>'),
                          ("b", "M8.4 17.2A3.9 3.9 0 0 0 15.6 17.2"), ("c", "M3.5 4.5H20.5V11H3.5Z")]},
  "r-kitchen":   {"els": [("raw", '<circle class="b" cx="7" cy="10.4" r="1"/><circle class="b" cx="10.4" cy="10.4" r="1"/>'
                                  '<circle class="b" cx="7" cy="13.6" r="1"/><circle class="b" cx="10.4" cy="13.6" r="1"/>'),
                          ("b", "M13.6 10H18.2V14H13.6Z"), ("c", "M3.5 7H20.5V17H3.5Z")]},
  "r-bathroom":  {"els": [("raw", '<rect class="b" x="6" y="9.5" width="12" height="5" rx="2.5"/>'),
                          ("d", dots([(8.3,12)], .7)),
                          ("raw", '<rect class="c" x="3.5" y="7" width="17" height="10" rx="2"/>')]},
  "r-dining":    {"els": [("b", "M9.8 3.5H14.2V5.5H9.8ZM9.8 18.5H14.2V20.5H9.8ZM3.5 9.8H5.5V14.2H3.5ZM18.5 9.8H20.5V14.2H18.5Z"),
                          ("raw", '<circle class="c" cx="12" cy="12" r="4.2"/>')]},
  "r-meeting":   {"els": [("b", "M6.8 5H9.2V6.8H6.8ZM10.8 5H13.2V6.8H10.8ZM14.8 5H17.2V6.8H14.8Z"
                                "M6.8 17.2H9.2V19H6.8ZM10.8 17.2H13.2V19H10.8ZM14.8 17.2H17.2V19H14.8Z"),
                          ("raw", '<rect class="c" x="5" y="9" width="14" height="6" rx="3"/>')]},
  "r-auditorium":{"els": [("b", "M7.5 4.5H16.5V7H7.5Z"),
                          ("c", "M7.5 9.86A7 7 0 0 0 11.03 11.43M12.97 11.43A7 7 0 0 0 16.5 9.86"
                                "M5.25 12.54A10.5 10.5 0 0 0 10.54 14.9M13.46 14.9A10.5 10.5 0 0 0 18.75 12.54"
                                "M3 15.22A14 14 0 0 0 10.05 18.36M13.95 18.36A14 14 0 0 0 21 15.22")]},
  "r-library":   {"els": [("b", "M7.75 4V8.5M12 4V8.5M16.25 4V8.5M7.75 15.5V20M12 15.5V20M16.25 15.5V20"),
                          ("c", "M3.5 4H20.5V8.5H3.5ZM3.5 15.5H20.5V20H3.5Z")]},
  "r-shop":      {"els": [("b", "M3.5 17H12.5V20.5H3.5Z"), ("d", dots([(10.4,18.75)], .7)),
                          ("c", "M3.5 3.5H7.5V14H3.5ZM10 3.5H14V14H10ZM16.5 3.5H20.5V14H16.5Z")]},
  "r-showroom":  {"els": [("raw", '<circle class="b" cx="6.5" cy="7" r="1.3"/><circle class="b" cx="17.5" cy="9.5" r="1.3"/>'
                                  '<circle class="b" cx="10.5" cy="17.5" r="1.3"/>'),
                          ("c", "M3.5 4H9.5V10H3.5ZM14.5 6.5H20.5V12.5H14.5ZM7.5 14.5H13.5V20.5H7.5Z")]},
  "r-bar":       {"els": [("b", "M3.5 3.25H20.5"),
                          ("raw", '<circle class="b" cx="6.5" cy="15.5" r="1.7"/><circle class="b" cx="12" cy="15.5" r="1.7"/>'
                                  '<circle class="b" cx="17.5" cy="15.5" r="1.7"/>'),
                          ("c", "M3.5 6.5H20.5V11H3.5Z")]},
  "r-spa":       {"els": [("b", "M7.5 10.6c1.5-1.2 3 1.2 4.5 0s3-1.2 4.5 0M7.5 13.8c1.5-1.2 3 1.2 4.5 0s3-1.2 4.5 0"),
                          ("raw", '<rect class="c" x="3.5" y="6" width="17" height="12" rx="5.5"/>')]},
  "r-lab":       {"els": [("b", "M3.5 12H20.5"),
                          ("raw", '<circle class="b" cx="8" cy="5" r="1.4"/><circle class="b" cx="16" cy="5" r="1.4"/>'
                                  '<circle class="b" cx="8" cy="19" r="1.4"/><circle class="b" cx="16" cy="19" r="1.4"/>'),
                          ("c", "M3.5 8.75H20.5V15.25H3.5Z")]},
  "r-mechanical":{"els": [("raw", '<circle class="b" cx="9" cy="12" r="3.3"/>'),
                          ("b", "M9 8.7V15.3M5.7 12H12.3M14.5 9H20.5M14.5 15H20.5"), ("c", "M3.5 5.5H14.5V18.5H3.5Z")]},
  "r-chapel":    {"els": [("b", "M9 12.5H15M9 15H15M9 17.5H15"), ("d", dots([(12,8.2)], .8)),
                          ("c", "M6 20.5V9.5A6 6 0 0 1 18 9.5V20.5Z")]},
  "r-storage":   {"clip": "M3.5 3.5H20.5V20.5H16.5V7.5H7.5V20.5H3.5Z",
                  "els": [("b", "M9.5 11.5H14.5V16.5H9.5ZM9.5 11.5L14.5 16.5M14.5 11.5L9.5 16.5"),
                          ("c", "M3.5 3.5H20.5V20.5H16.5V7.5H7.5V20.5H3.5Z")]},
  "r-service":   {"els": [("b", "M4.5 4.5L19.5 19.5M19.5 4.5L4.5 19.5"), ("c", "M4.5 4.5H19.5V19.5H4.5Z")]},
  "r-stairs":    {"els": PSTAIR},
  "r-atrium":    {"els": [("b", "M8 8H16V16H8ZM8 16L16 8"), ("c", FRAME)]},
  "r-lounge":    {"els": [("raw", '<rect class="b" x="7" y="14.5" width="10" height="5" rx="2.5"/>'),
                          ("raw", '<rect class="c" x="3.5" y="4.5" width="6" height="6" rx="1.6"/>'
                                  '<rect class="c" x="14.5" y="4.5" width="6" height="6" rx="1.6"/>')]},
  "r-window":    {"clip": "M2.75 14.5H6.5V19H2.75ZM17.5 14.5H21.25V19H17.5Z",
                  "els": [("b", "M6.5 14.5H17.5M6.5 16.75H17.5M6.5 19H17.5M7 5H17V11H7Z"), ("d", dots([(10,8),(14,8)], .8)),
                          ("c", "M2.75 14.5H6.5V19H2.75M21.25 14.5H17.5V19H21.25")]},
  "r-counter":   {"clip": "M3.5 6.5H20.5V17.5H16V11H3.5Z",
                  "els": [("raw", '<circle class="b" cx="9" cy="15.75" r="1.7"/>'), ("c", "M3.5 6.5H20.5V17.5H16V11H3.5Z")]},
  "r-other":     {"els": [("d", dots([(6.5,12),(12,12),(17.5,12)], 1.2))]},
}

def symbol(name, spec):
    out = []
    if "clip" in spec:
        out.append(f'<clipPath id="cp-{name}"><path d="{spec["clip"]}"/></clipPath>')
    out.append(f'<symbol id="i-{name}" viewBox="0 0 24 24">')
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
    mock("Room", "Proposed: furniture in plan", res("r-"), "ic", 1),
    mock("Materiality", "Now: system symbols", mat("m-"), "sf", 0),
    mock("Materiality", "Proposed: hatch swatches", mat("m-"), "ic", 0),
])

TEMPLATE = io.open(os.path.join(HERE, "template.html"), encoding="utf-8").read()
html = (TEMPLATE.replace("__SFCSS__", sf_css()).replace("__HATCH__", HATCH).replace("__FRAME__", FRAME)
        .replace("__SYMBOLS__", SYMBOLS).replace("__MATRIX__", matrix_rows)
        .replace("__ROOMS__", room_pairs).replace("__MATERIALS__", mat_pairs).replace("__MOCKS__", MOCKS))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
io.open(OUT, "w", encoding="utf-8").write(html)
print(f"wrote {OUT}  {len(html)//1024} KB  ·  {len(ICONS)} proposed symbols")
