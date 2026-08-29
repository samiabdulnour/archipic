# Archipic — upgrade brief

A backlog for Claude Code, ordered by leverage. The goal behind all of it: the
app is excellent but invisible, because nothing it produces ever leaves the
device. These changes make it easier to get references *in*, and make what comes
*out* worth showing to someone else.

Work top to bottom. Each task is independent enough to ship on its own. Do not
batch several tasks into one PR.

## Read first

- `CLAUDE.md` — product principles and architecture. The six principles are
  binding.
- `Photo.swift` — the model, `HumanTags`, and the non-destructive edit fields.
- `BUILD-IOS.md` — release procedure, including when a CloudKit schema deploy
  is required.
- `APPSTORE.md` — listing copy.

## Global constraints

- **Privacy is a promise on the store listing.** No analytics, no third-party
  SDKs, no network calls to anything but the user's own iCloud. Anything that
  would change the App Privacy answers away from "Data Not Collected" is out of
  scope and must be raised with the owner instead of built.
- **Never merge `tagsMachine` into `tagsHuman`.**
- **Never mutate source pixels.** All new visual output goes through the
  existing non-destructive edit pipeline.
- **Adding a field to the SwiftData model means a CloudKit schema deploy before
  release.** Prefer adding keys inside the `humanTagsData` JSON blob, which
  needs no deploy. Say explicitly in the PR description which of the two you did.
- Ask before touching capture, backup/restore, or the store.

---

## 1. Share Sheet extension

**Why.** Half of how architects collect references today is saving images from
Instagram, Pinterest, a browser, or a PDF. Right now those can only enter the
archive by going through Photos and then importing. A share extension makes
Archipic the destination for any image on the phone, which is the single biggest
increase in how often the app gets used.

**Build.**
- New target: a Share extension accepting `public.image` (and `public.url` if
  cheap, saving the page's preview image).
- Add an **App Group** so the extension and the app can share a container, and
  move the SwiftData store into it. **This is the risky part** — it changes
  where the store lives for existing users. Write a one-time migration that
  moves the existing store into the group container and verify it against a
  populated archive before merging. If the migration cannot be made safe,
  fall back to the extension writing a small inbox file that the app drains on
  next launch, and say so.
- The extension UI is minimal: a thumbnail, the type picker (Building /
  Element / Graphic), and Save. Full tagging happens in the app.
- Saved items get `importedAt` set and no `assetLocalID`.

**Done when.** Sharing an image from Safari and from Photos both land a tagged
record in the archive, the record survives an app relaunch, and an existing
archive is intact after upgrading.

---

## 2. Shareable Board export

**Why.** Boards already produce a print-ready PDF. That PDF is the only thing
this app makes that a person would ever post publicly, and it is the only
mechanism by which a stranger finds out Archipic exists. Treat it as the growth
surface.

**Build.**
- Alongside the existing PDF export, add **image export** at social sizes:
  square 1080×1080, portrait 1080×1350, and story 1080×1920. Reuse
  `BoardRenderer`; do not fork the layout code.
- Add an optional, default-on attribution mark — small, typographic, bottom
  corner, using the app mark. A single Settings toggle turns it off. Do not
  make it a watermark over the image.
- Route through the standard share sheet so it reaches Instagram, Messages and
  Files in one step.

**Done when.** A board can be exported as a correctly-sized image with and
without the mark, and the layout matches the PDF at the new aspect ratios rather
than being letterboxed.

---

## 3. On-device tag suggestions into `tagsMachine`

**Why.** Two taps is good; a pre-filled guess the user confirms is better, and
`machineTagsData` has been reserved for this since the first version.

**Build.**
- First read `Tagging/TagSuggester.swift` and report what it already does before
  writing anything — do not duplicate existing behaviour.
- Use the **Vision** framework on-device only: classification for
  Building/Element/Graphic, plus text recognition on Graphic captures to
  pre-fill title, creator and year from a book page or a wall label. Nothing
  leaves the device.
- Write results to `machineTagsData`. Present them in the tag sheet as
  *suggestions* — visually distinct, one tap to accept. Accepting copies the
  value into `tagsHuman`; the machine record stays.
- Run asynchronously after capture. Capture speed must not regress.

**Done when.** A photo of a book page suggests Graphic and pre-fills any legible
title text, suggestions are visually distinguishable from confirmed tags, and
capture-to-tag-sheet time is unchanged.

---

## 4. Metadata on export (IPTC / XMP)

**Why.** Architects finish work in InDesign, Lightroom and Bridge. If the tags
survive an export, Archipic becomes part of a professional workflow instead of
a place data goes to die. It is also the honest version of a lock-in-free app.

**Build.**
- When exporting photos (single, multi-select, and the full backup), write tags
  into the image metadata: `IPTC:Keywords` from the flattened taxonomy plus
  free keywords, `IPTC:Caption-Abstract` from the note, `XMP:Title`,
  `XMP:Creator` and `XMP:Rating`, and preserve GPS and the original capture date.
- Use ImageIO (`CGImageDestination` with the properties dictionary). No new
  dependency.
- Add a Settings toggle to strip GPS on export, defaulting to *keep*, since
  location is what makes the archive useful, but a user sharing publicly needs
  the option.

**Done when.** An exported JPEG opened in Preview's inspector or Lightroom shows
the keywords, caption and rating, and the GPS toggle works both ways.

---

## 5. App Intents — Shortcuts, Action Button, Lock Screen

**Why.** The whole premise is capture in under ten seconds. Unlocking, finding
the icon and waiting for launch is most of that time.

**Build.**
- An `AppIntent` for capture that opens straight into the camera, exposed to
  Shortcuts, the Action Button, Siri and Spotlight.
- Optional parameters so a shortcut can pre-select a project or a type, e.g.
  "capture into project X".
- Check `ArchiveWidgetsControl.swift` first — a Control Centre control already
  exists and the intent should be shared, not duplicated.
- Add an intent for "add last photo from Photos to Archipic" if it is cheap.

**Done when.** Holding the Action Button opens the viewfinder from a locked
phone, and a Shortcut can capture directly into a named project.

---

## 6. iPad support

**Why.** Curating references and composing Boards are big-screen tasks. Boards
in particular is a layout tool squeezed onto a phone. It also opens the "Designed
for iPad" and Mac App Store listings.

**Build.**
- Enable the iPad destination. Audit every view for hardcoded phone geometry.
- Use a `NavigationSplitView` on regular size classes: lenses and filters in the
  sidebar, grid in the detail pane.
- Board composer gets a proper two-pane layout: photo well on one side, live
  board preview on the other, with drag to reorder.
- Camera on iPad can stay minimal — iPad is for reviewing, not shooting.
- Keyboard shortcuts for the gallery: arrow keys, space to favourite, delete.

**Done when.** The app runs on iPad in portrait and landscape with no clipped or
stretched layout, and the Board composer is usable with a trackpad.

---

## 7. Ratings prompt

**Why.** The listing currently has too few ratings for the App Store to display
a rating at all, which is the most damaging thing about the page.

**Build.**
- `requestReview` via `@Environment(\.requestReview)`, triggered after a genuine
  success moment — the first Board export, or after the 50th photo is tagged —
  never on launch and never after an error.
- Gate it with a stored flag so it fires at most once per version, and only
  after the user has been using the app for more than a few days.

**Done when.** The prompt appears after a board export on a mature archive and
never appears twice.

---

## 8. Localisation

**Why.** Architecture is a global profession and the app is English-only.

**Build.**
- Extract all user-facing strings into a String Catalog (`.xcstrings`). This is
  the whole task for now — no translations yet.
- The tag vocabulary is the hard part: the *stored* values must stay the current
  lowercase English identifiers, and only the *displayed* labels get localised,
  so that sync and search stay stable across languages. Confirm this holds in
  `TagVocabulary.swift` before extracting.
- Target languages once strings are extracted: German, French, Spanish, Italian.

**Done when.** No user-facing literal remains inline, and switching the device
language changes labels without changing any stored tag value.

---

## Not code — for the owner, not the agent

These matter more than any of the above but do not belong in a PR:

- Rewrite the App Store description. The live one is 1.0 copy and never mentions
  video, Boards, film looks or widgets.
- Fix `docs/index.html` — the "Download on the App Store" button is still
  `href="#"`.
- Rename on the store to include a searchable keyword, e.g.
  `Archipic: Architecture Archive` (30 chars). Keep `CFBundleDisplayName` as
  `Archipic`.
- Shoot an App Preview video: capture, two taps, gallery, Board.
- Replace the AI-generated screenshots in `AppStoreScreenshots/` with real ones.
