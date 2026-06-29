#!/usr/bin/env python3
"""Generate 5 App Store screenshots for Archi.vé at 1320×2868px (iPhone 17 Pro Max)."""

import subprocess, os, textwrap

W, H = 1320, 2868
OUT = "/Users/Sami/Code/archi-ve/AppStoreScreenshots"
PAPER = "#F5F0E8"; INK = "#1A1A1A"; INK2 = "#5A5A5A"; INK3 = "#9A9A9A"
CORAL = "#E3523A"; LEMON = "#EDE34A"; TILE = "#E8E3DA"; WHITE = "#FFFFFF"

# ── helpers ──────────────────────────────────────────────────────────────────

def svg(body, defs=""):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
  <style>text {{ font-family: -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif; }}</style>
  {defs}
</defs>
{body}
</svg>"""

def rect(x,y,w,h,fill,rx=0,opacity=1,stroke=None,sw=1):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" rx="{rx}" opacity="{opacity}"{s}/>'

def text(x,y,s,size=30,fill=INK,weight="regular",anchor="middle",opacity=1):
    fw = "600" if weight=="semibold" else ("700" if weight=="bold" else "400")
    return f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{fw}" fill="{fill}" text-anchor="{anchor}" opacity="{opacity}" dominant-baseline="middle">{s}</text>'

def pill_toggle(labels, sel_idx, x, y, gap=6, ph=66, pfont=28):
    """Horizontal pill toggle row; selected gets lemon fill."""
    total_w = W - 2*x
    pw = (total_w - gap*(len(labels)-1)) // len(labels)
    out = []
    for i,lbl in enumerate(labels):
        px = x + i*(pw+gap)
        fill = LEMON if i==sel_idx else PAPER
        out.append(rect(px,y,pw,ph,fill,rx=ph//2))
        fw = "semibold" if i==sel_idx else "regular"
        out.append(text(px+pw//2, y+ph//2+1, lbl, size=pfont, fill=INK, weight=fw))
    return "\n".join(out)

def nav_bar(title, y=162, cam=True, right="..."):
    out = [rect(0,y,W,132,PAPER)]
    if cam:
        out.append(text(66,y+66,"⊙",36,INK,"regular"))
    out.append(f'<text x="{W//2}" y="{y+67}" font-size="40" font-weight="600" text-anchor="middle" dominant-baseline="middle">'
               f'<tspan fill="{INK}">Archi.</tspan><tspan fill="{CORAL}">vé</tspan></text>')
    out.append(text(W-66,y+66,right,36,INK,"regular"))
    return "\n".join(out)

def search_bar(y=294):
    out = [rect(0,y,W,132,PAPER)]
    out.append(rect(48,y+30,W-96,72,TILE,rx=36))
    out.append(text(W//2,y+66,"Search",30,INK3))
    return "\n".join(out)

def status_bar_light():
    return f"""
{rect(0,0,W,162,PAPER)}
<rect x="504" y="18" width="312" height="54" fill="{INK}" rx="27"/>
{text(120,81,"9:41",36,INK,"semibold","start")}
{text(W-120,81,"●●●  ▲  ▐▌",30,INK,"regular","end")}"""

def status_bar_dark():
    return f"""
{rect(0,0,W,162,"#000000")}
<rect x="504" y="18" width="312" height="54" fill="{INK}" rx="27"/>
{text(120,81,"9:41",36,WHITE,"semibold","start")}
{text(W-120,81,"●●●  ▲  ▐▌",30,WHITE,"regular","end")}"""

# ── architectural photo tile generator ───────────────────────────────────────
# sips SVG renderer doesn't support fill="url(#id)" gradient references —
# use solid-colour diagonal two-tone compositions instead.

PHOTO_STYLES = [
    # (id, c1_light, c2_dark, style)
    ("p01","#8FBBCC","#3A6A8A","concrete"),    # blue-grey concrete
    ("p02","#C47B5B","#7A3D28","terracotta"),   # warm brick/terracotta
    ("p03","#9BA8B5","#5A6878","steel"),         # cool steel curtain wall
    ("p04","#BEA96B","#7A6A35","stone"),         # warm limestone/stone
    ("p05","#5C4535","#2E2018","timber"),         # dark timber
    ("p06","#E0DDD4","#B0ADA6","plaster"),        # pale white plaster
    ("p07","#7AABCC","#2A5A8A","glass"),          # blue glass facade
    ("p08","#B5584A","#7A3028","brick"),           # red brick
    ("p09","#9A9A9A","#4A4A4A","grey"),            # raw concrete grey
    ("p10","#C4956B","#8A5A35","heritage"),        # warm heritage sandstone
    ("p11","#E8C87A","#C4A030","interior"),        # golden interior light
    ("p12","#7A9A8B","#4A6A5A","landscape"),       # green/grey landscape
]

def photo_defs(): return ""   # no longer needed
def vignette_defs(): return ""

def photo_tile(x, y, w, h, style_idx, label=None):
    _, c1, c2, style = PHOTO_STYLES[style_idx % len(PHOTO_STYLES)]
    out = []
    # Base: lighter colour fills the whole tile
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{c1}"/>')
    # Diagonal darker triangle bottom-right — creates depth without url() gradients
    out.append(f'<polygon points="{x+w},{y} {x+w},{y+h} {x},{y+h}" fill="{c2}"/>')
    # Style-specific architectural detail lines
    if style in ("concrete", "grey"):
        for j in range(1, 4):
            ly = y + h*j//4
            out.append(f'<line x1="{x}" y1="{ly}" x2="{x+w}" y2="{ly}" stroke="{c2}" stroke-width="2" opacity="0.35"/>')
    elif style == "steel":
        for j in range(1, 6):
            lx = x + w*j//6
            out.append(f'<line x1="{lx}" y1="{y}" x2="{lx}" y2="{y+h}" stroke="{c1}" stroke-width="2" opacity="0.45"/>')
    elif style == "terracotta":
        for j in range(1, 5):
            ly = y + h*j//5
            out.append(f'<line x1="{x}" y1="{ly}" x2="{x+w}" y2="{ly}" stroke="{c2}" stroke-width="4" opacity="0.30"/>')
    elif style == "brick":
        for j in range(1, 6):
            ly = y + h*j//6
            out.append(f'<line x1="{x}" y1="{ly}" x2="{x+w}" y2="{ly}" stroke="{c2}" stroke-width="3" opacity="0.40"/>')
    elif style == "glass":
        for j in range(1, 5):
            lx = x + w*j//5
            out.append(f'<rect x="{lx}" y="{y}" width="{w//12}" height="{h}" fill="{c1}" opacity="0.28"/>')
    elif style == "heritage":
        for j in range(2):
            ax = x + w//4 + j*w//2; ay = y + h//3; ar = w//8
            out.append(f'<rect x="{ax-ar//2}" y="{ay}" width="{ar}" height="{ar*2}" fill="{c2}" opacity="0.45" rx="{ar//2}"/>')
    elif style == "interior":
        out.append(f'<rect x="{x+w//4}" y="{y}" width="{w//2}" height="{h}" fill="{c1}" opacity="0.25"/>')
    # label badge
    if label:
        lw = len(label)*14 + 24
        out.append(rect(x+8,y+10,lw,40,LEMON,rx=20))
        out.append(text(x+8+lw//2,y+30,label,22,INK,"semibold"))
    return "\n".join(out)

# ── SCREENSHOT 1: Camera ──────────────────────────────────────────────────────
def make_camera():
    body = f"""
{status_bar_dark()}
{rect(0,162,W,H-162,"#000000")}
<!-- type selector pills -->
<rect x="30" y="198" width="252" height="90" fill="rgba(255,255,255,0.15)" rx="45"/>
{text(93,243,"▦",28,WHITE)}
{text(155,243,"▣",28,WHITE)}
{text(217,243,"▤",28,WHITE)}
<!-- right controls -->
<rect x="{W-294}" y="198" width="264" height="90" fill="rgba(255,255,255,0.15)" rx="45"/>
{text(W-234,243,"🏷",26,CORAL)}
{text(W-162,243,"↺",28,WHITE)}
{text(W-90,243,"⊞",28,WHITE)}
<!-- grid lines -->
<line x1="0" y1="588" x2="{W}" y2="588" stroke="rgba(255,255,255,0.18)" stroke-width="1.5"/>
<line x1="0" y1="1176" x2="{W}" y2="1176" stroke="rgba(255,255,255,0.18)" stroke-width="1.5"/>
<line x1="0" y1="1764" x2="{W}" y2="1764" stroke="rgba(255,255,255,0.18)" stroke-width="1.5"/>
<line x1="440" y1="450" x2="440" y2="2100" stroke="rgba(255,255,255,0.18)" stroke-width="1.5"/>
<line x1="880" y1="450" x2="880" y2="2100" stroke="rgba(255,255,255,0.18)" stroke-width="1.5"/>
<!-- level indicator -->
<line x1="480" y1="1176" x2="840" y2="1176" stroke="rgba(255,255,255,0.75)" stroke-width="3"/>
<circle cx="{W//2}" cy="1176" r="8" fill="rgba(255,255,255,0.7)"/>
<!-- gallery thumbnail -->
<rect x="48" y="{H-354}" width="168" height="168" fill="{PHOTO_STYLES[0][1]}" rx="18"/>
<rect x="48" y="{H-354}" width="84" height="168" fill="{PHOTO_STYLES[0][2]}" rx="0"/>
<rect x="48" y="{H-354}" width="168" height="168" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="2" rx="18"/>
<!-- REFERENCE/PROJECT pills -->
<rect x="222" y="{H-348}" width="270" height="78" fill="{LEMON}" rx="39"/>
{text(357,H-309,"REFERENCE",26,INK,"semibold")}
{text(594,H-309,"PROJECT",26,"rgba(255,255,255,0.6)","regular")}
<!-- shutter button -->
<circle cx="{W//2}" cy="{H-528}" r="100" fill="none" stroke="rgba(255,255,255,0.9)" stroke-width="6"/>
<circle cx="{W//2}" cy="{H-528}" r="78" fill="{WHITE}"/>
<!-- flip -->
<circle cx="{W-90}" cy="{H-288}" r="54" fill="rgba(255,255,255,0.12)"/>
{text(W-90,H-288,"↺",34,WHITE)}
"""
    return svg(body)

# ── SCREENSHOT 2: Gallery grid ─────────────────────────────────────────────────
def make_gallery():
    PW = 438; GAP = 2; COLS = 3; ROWS = 5
    grid_y = 558
    labels = [
        "Aalto House","Brick",None,"Stair","Aalto House",
        None,"Exhibition","Civic",None,"Heritage",
        "Residential",None,None,"Stair","Civic"
    ]
    photos = []
    for r in range(ROWS):
        for c in range(COLS):
            idx = r*COLS+c
            x = c*(PW+GAP); y = grid_y + r*(PW+GAP)
            photos.append(photo_tile(x,y,PW,PW,idx,labels[idx] if idx<len(labels) else None))
    body = f"""
{rect(0,0,W,H,PAPER)}
{status_bar_light()}
{nav_bar("Archi.vé")}
{search_bar(294)}
{pill_toggle(["Time","Reference","Project","Map"],0,48,438,gap=12,ph=78,pfont=30)}
{"".join(photos)}
"""
    return svg(body)

# ── SCREENSHOT 3: Tag detail – Building typology ──────────────────────────────
def make_tagging():
    PHOTO_H = 2052  # sized so 2 icon rows flush to screen bottom (PHOTO_H+372+444=2868)
    typo = [
        ("🏠","Residential"),("🏢","Office"),("🏛","Public"),
        ("🏬","Commercial"),("🚩","Civic"),("🏨","Hospitality"),
        ("🏺","Heritage"),("⚙","Industrial"),("🌳","Landscape"),("●●●","Other"),
    ]
    ICON_W = 220; ICON_H = 210; COLS_T = 5
    grid_y = PHOTO_H + 162 + 90 + 120
    icon_tiles = []
    for i,(icon,lbl) in enumerate(typo):
        c = i % COLS_T; r = i // COLS_T
        x = 48 + c*(ICON_W+18); y = grid_y + r*(ICON_H+12)
        fill = LEMON if i==0 else PAPER
        icon_tiles.append(rect(x,y,ICON_W,ICON_H,fill,rx=20))
        icon_tiles.append(text(x+ICON_W//2,y+ICON_H//2-28,icon,52,INK))
        icon_tiles.append(text(x+ICON_W//2,y+ICON_H-42,lbl,22,INK,"semibold"))
    body = f"""
{rect(0,0,W,H,PAPER)}
{status_bar_light()}
{rect(0,162,W,132,PAPER)}
{text(90,228,"‹",54,INK,"regular","middle")}
{text(W//2,228,"29.6.2026 at 9:41",34,INK,"regular")}
{text(W-66,228,"⋯",40,INK,"regular")}
{photo_tile(0,294,W,PHOTO_H,0,None)}
{pill_toggle(["Building","Element","Graphic"],0,48,PHOTO_H+294+24,gap=18,ph=78,pfont=32)}
{text(66,PHOTO_H+294+24+78+72,"Typology",34,INK,"semibold","start")}
{"".join(icon_tiles)}
"""
    return svg(body)

# ── SCREENSHOT 4: Reference lens (dual pill rows) ─────────────────────────────
def make_reference():
    PW = 438; GAP = 2
    labels2 = [
        "Aalto House",None,"Exhibition","Civic",None,None,
        "Heritage",None,"Stair",None,None,"Residential",
        "Aalto House","Brick",None
    ]
    photos = []
    grid_y = 690
    for r in range(5):  # 5th row clips at bottom — suggests more content
        for c in range(3):
            idx = r*3+c
            x = c*(PW+GAP); y = grid_y + r*(PW+GAP)
            photos.append(photo_tile(x,y,PW,PW,(idx+3)%len(PHOTO_STYLES),labels2[idx]))
    body = f"""
{rect(0,0,W,H,PAPER)}
{status_bar_light()}
{nav_bar("Archi.vé")}
{search_bar(294)}
{pill_toggle(["Time","Reference","Project","Map"],1,48,438,gap=12,ph=78,pfont=30)}
{pill_toggle(["All","Building","Element","Graphic"],0,48,546,gap=12,ph=78,pfont=30)}
{"".join(photos)}
"""
    return svg(body)

# ── SCREENSHOT 5: Photo detail – Element taxonomy ─────────────────────────────
def make_element():
    PHOTO_H = 1920  # sized so mats section flushes to screen bottom (PHOTO_H+372+444+130=2866)
    elements = [
        ("⌐","Wall"),("═","Floor"),("⊓","Ceiling"),("⊏","Column"),("↕","Stair"),
        ("▦","Facade"),("⊟","Door"),("▣","Window"),("⊞","Roof"),("●●●","Other"),
    ]
    ICON_W = 220; ICON_H = 210; COLS_T = 5
    grid_y = PHOTO_H + 162 + 90 + 120
    icon_tiles = []
    for i,(icon,lbl) in enumerate(elements):
        c = i % COLS_T; r = i // COLS_T
        x = 48 + c*(ICON_W+18); y = grid_y + r*(ICON_H+12)
        fill = LEMON if lbl=="Stair" else PAPER
        icon_tiles.append(rect(x,y,ICON_W,ICON_H,fill,rx=20))
        icon_tiles.append(text(x+ICON_W//2,y+ICON_H//2-22,icon,48,INK))
        icon_tiles.append(text(x+ICON_W//2,y+ICON_H-42,lbl,22,INK,"semibold"))
    mats_y = grid_y + 2*(ICON_H+12) + 60
    mat_labels = ["Concrete","Timber","Glass"]
    mat_tiles = []
    for i,m in enumerate(mat_labels):
        mat_tiles.append(rect(66+i*240,mats_y,220,70,LEMON if i==0 else PAPER,rx=35))
        mat_tiles.append(text(66+i*240+110,mats_y+35,m,26,INK,"semibold"))
    body = f"""
{rect(0,0,W,H,PAPER)}
{status_bar_light()}
{rect(0,162,W,132,PAPER)}
{text(90,228,"‹",54,INK,"regular","middle")}
{text(W//2,228,"29.6.2026 at 9:41",34,INK,"regular")}
{text(W-66,228,"⋯",40,INK,"regular")}
{photo_tile(0,294,W,PHOTO_H,1,None)}
{pill_toggle(["Building","Element","Graphic"],1,48,PHOTO_H+294+24,gap=18,ph=78,pfont=32)}
{text(66,PHOTO_H+294+24+78+72,"Element",34,INK,"semibold","start")}
{"".join(icon_tiles)}
{text(66,mats_y-48,"Materiality",34,INK,"semibold","start")}
{"".join(mat_tiles)}
"""
    return svg(body)

# ── render ────────────────────────────────────────────────────────────────────
shots = [
    ("01_camera.png",    make_camera()),
    ("02_gallery.png",   make_gallery()),
    ("03_tagging.png",   make_tagging()),
    ("04_reference.png", make_reference()),
    ("05_element.png",   make_element()),
]

for fname, content in shots:
    svg_path = f"/tmp/{fname.replace('.png','.svg')}"
    png_path = f"{OUT}/{fname}"
    with open(svg_path,"w") as f: f.write(content)
    result = subprocess.run(
        ["sips","--setProperty","format","png",svg_path,"--out",png_path],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        r = subprocess.run(["sips","-g","pixelWidth","-g","pixelHeight",png_path],
                           capture_output=True,text=True)
        dims = " ".join(r.stdout.split())
        print(f"✓ {fname}  {dims}")
    else:
        print(f"✗ {fname}: {result.stderr[:120]}")
