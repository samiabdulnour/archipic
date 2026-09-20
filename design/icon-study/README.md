# Tag icon study

Working files for the custom tag icons (outline style). Nothing here ships in the app yet.

- `build.py` holds every proposed icon as SVG path data on a 24-unit grid, and builds the
  review page from `template.html` into `out/`.
- `render-current-icons.swift` renders the app's *current* icons (SF Symbols, 21 pt, fill
  variant, exactly as `TagForm.symbolArt` draws them) to PNG for side-by-side comparison.
  Build it for the simulator and run it with `xcrun simctl spawn booted ./sfrender ./sf`.

`sf/` and `out/` are ignored on purpose: the renders are Apple's artwork and must not be
redistributed, and the page embeds them.

Drawing rules: heavy line = the thing the tag names; light line = its detail and what
surrounds it. Elements exist as a section set (`s-`) and a plan set (`p-`); rooms (`r-`)
are furniture in plan; materials (`m-`) are hatch swatches.
