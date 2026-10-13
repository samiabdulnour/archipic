# Archipic

A private photo journal for architects. The user photographs architecture they
encounter — a façade on a walk, a joint at an exhibition, a plan in a book, a
site in progress — tags it with a small structured vocabulary in about two taps,
and finds it again later by what it is, when it was taken, which project it
belongs to, or where it was found.

Shipped on the App Store as a free, native app for iPhone and iPad (it also
runs on Apple silicon Macs and Vision Pro as an iPad app). App Store ID
`6777989742`, bundle ID `com.samiabdulnour.archive`, Team `N6QDF49V2G`,
iOS 17+.

---

## Product principles

These are the rules the app is judged against. Anything that breaks one of them
needs to be discussed with the owner before it is built.

1. **Capture is fast.** Open, shoot, tag, done — usable while walking. Typing on
   a phone on a sidewalk is the enemy, so tags are buttons, not text fields.
2. **The vocabulary is small and fixed.** A consistent taxonomy beats free-form
   keywords, because it is what makes the archive searchable years later.
3. **Human tags and machine tags never merge.** `tagsHuman` is what the user
   said; `tagsMachine` is what software guessed. Keep them separate forever so
   intent and guesses stay distinguishable.
4. **Edits are non-destructive.** Looks, crop, rotation, straighten and keystone
   are stored as parameters and applied on display. The source pixels are never
   altered.
5. **Nothing leaves the device except to the user's own iCloud.** No accounts,
   no ads, no analytics, no third-party SDKs, no developer server. This is a
   promise made on the App Store listing and it constrains every feature.
6. **Photos are never lost.** Anything touching the data model, the capture
   path, or the store must be conservative. Ask before changing it.

---

## Who it is for

Working architects, architecture students, and anyone who collects visual
references from the built world. Single-user by design: one person, their own
archive, synced across their own devices. Not collaborative, no sharing of
libraries, no multi-user features.

---

## Architecture

Native SwiftUI, built and shipped from `Archipic/Archipic.xcodeproj`. Three
targets: the app (`Archipic`), a widget extension (`ArchipicWidgetsExtension`)
and a Share extension (`ShareExtension`, which writes shared images to an App
Group inbox that the app drains on launch; the store never moves).

- **Persistence:** SwiftData, models `Photo` and `Board`.
- **Sync:** CloudKit private database via
  `ModelConfiguration(cloudKitDatabase: .automatic)`. The developer cannot read
  any of it.
- **Camera:** AVFoundation, hand-built viewfinder — grid, level, aspect guides,
  tap-to-focus and exposure, pinch zoom, film-inspired colour looks, photo and
  video modes.
- **Location:** CoreLocation, captured with the photo so the Map lens works.
  Requested only while capturing.
- **Maps:** MapKit.
- **Crash recovery:** if the SwiftData store fails to open, `ArchipicApp` moves
  it aside as `default.store.corrupt-<timestamp>` (never deletes it) and retries
  once, letting CloudKit re-populate a fresh store. This exists to prevent a
  permanent launch crash-loop that would lock the user out of their own archive.

### File map

```
Archipic/Archipic/
  ArchipicApp.swift        App entry, ModelContainer, store recovery
  ContentView.swift       Root navigation
  Photo.swift             Photo model + HumanTags + TagClipboard
  PhotosLibrary.swift     Photos-library access and asset loading
  QuickCapture.swift      Fast capture entry point
  Palette.swift           Colour tokens
  Camera/                 AVFoundation capture, looks, level, video, picker
  Tagging/                Tag sheet, form, vocabulary, suggester, photo editor
  Gallery/                Grid, library, reference lens, detail, video playback
  Print/                  Boards: model, composer, PDF renderer, geocoder
  Settings/               Welcome, how-to, about, sync monitor
Archipic/ArchipicWidgets/   Home Screen, Lock Screen and Control Centre widgets
Archipic/ShareExtension/    "Save to Archipic" from the system share sheet
```

---

## Data model

`Photo` (SwiftData, CloudKit-synced):

- `id` — UUID string. **No `.unique` constraint** — CloudKit forbids it.
  Uniqueness is enforced by generating UUIDs and de-duping by id on import.
- `imageData` — external storage. The JPEG, or for video the poster frame.
  Empty when the pixels live in the Photos library.
- `assetLocalID` — set when the record is a *reference* to a photo in the
  system Photos library rather than a copy. `isReference` derives from it.
- `isVideo`, `videoData` — video lives in Photos where possible; `videoData` is
  the in-app fallback when saving to Photos was not permitted.
- `createdAt`, `latitude`, `longitude` — capture time and place.
- `humanTagsData` / `machineTagsData` — JSON blobs. JSON rather than columns so
  the taxonomy can evolve without a SwiftData migration and without a CloudKit
  schema deploy for every tweak.
- `project`, `isFavorite`, `importedAt`, `isCameraShot`, `labelImageData`
  (a second shot of a wall label or placard, captured instead of typing it).
- Non-destructive edits: `editLookRaw`, `editKeystone`, `editRotation`,
  `editStraighten`, `cropX/Y/W/H`. `hasEdits` lets display skip the pipeline
  entirely for untouched photos.
- `searchText` — denormalised lower-cased text of every tag value, for
  AND word-match search.

`HumanTags` is a `Codable` struct, all fields optional or arrays so a
half-tagged draft is representable.

---

## Tag vocabulary

Tap one picks the **type**; the following fields depend on it.

- **Building** — the whole thing. Typology (residential, office, public,
  commercial, civic, hospitality, heritage, industrial, landscape), room,
  concepts.
- **Element** — a part of it. Element category and element (structure,
  openings, envelope, finishes, details), materials, colours.
- **Graphic** — a flat reference. Kind (artwork, book, drawing, plan, render,
  model, web), visual character, plus per-kind detail fields: title, creator,
  year, source, brand, model, contact name and company.

Optional across all types: author/year, note, place, free keywords, 1–5 rating.
Fields are configurable — the user turns on only the ones they want.

Time and GPS come free from the phone and are never tagged by hand. Project is
chosen separately, not part of the taxonomy.

`TagClipboard` copies one photo's taxonomy and pastes it onto another.
`mergingTaxonomy(from:)` deliberately keeps the target's own place, note,
rating, keywords and graphic details, so pasting never wipes hand-typed values.

---

## Browsing

Four lenses over the same archive: **Time**, **Reference** (grouped by what is
in the photo), **Project**, and **Place** (map). Plus search across every tag,
filters by type, project, favourites and minimum rating, and a pinch-resizable
grid that remembers its preferred photos-per-row.

**Boards** compose any selection into a print-ready B1 poster (a justified
gallery wall) or an A4 landscape journal, with captions drawn from the tags,
exported as PDF.

---

## Shipped so far

- **1.0** — Two-tap capture, the Building/Element/Graphic taxonomy, native
  camera, gallery by time/reference/project/place, search and filters,
  favourites and ratings, and private iCloud sync.
- **1.3** — Video capture and playback, a new app mark (a filled disc in a
  technical dash-dot ring) carried through the app and the widgets, a single
  unified camera for Reference and Project capture, colour looks rebuilt from
  measured colour, Boards, and a smoother gallery.
- **1.4** (28 September 2026) — iPad (sidebar for the four lenses, two-pane
  Board composer, landscape), saving from the system share sheet, a Capture
  action for Shortcuts, Siri and the Action Button, find-a-tag-by-name,
  on-device title/author/year suggestions from a book page or wall label,
  tags exported as IPTC/XMP metadata, and Boards as square, portrait and
  story images.

---

## Website

`docs/` is served by GitHub Pages at **archipic.app** (see `docs/CNAME`):
landing page, `privacy.html`, `support.html` and `press.html` (with the press
kit in `docs/press/`). Privacy and support are required by App Store Connect
and must stay reachable. Merging to `main` deploys the site, so run
`python3 tools/check-site-links.py` first.

archipic.app is the permanent domain, and Board exports print it. The old
address, archi-ve.app, forwards every page to archipic.app through a separate
repository, `samiabdulnour/archi-ve-redirect`; keep it (see `BUILD-IOS.md` →
"Website and domain").

The privacy promise covers the website too: no analytics, tracking pixels,
third-party scripts, or campaign parameters on links. Public copy follows the
house style in `BUILD-IOS.md` → "Promotion, every release". The press bio is
"Sami Abdulnour, a Czech architect"; never name the owner's employer.

---

## Working with the owner

- The owner is an architect who is learning to program through this project.
  Explain non-trivial code when adding it, in plain language.
- Prefer small working increments over big leaps.
- Before adding a dependency or a new pattern, explain the trade-off and ask.
- When the owner reports a bug they describe the *symptom*. Debug from that
  rather than assuming a cause.
- Commit at the end of each working stage with a clear message.
- **Auto-merge:** for changes the agent wrote, squash-merge the PR into `main`
  without waiting for manual review. Because of this, be conservative: no
  speculative refactors.
- **Always ask first** before anything that touches the SwiftData schema,
  CloudKit sync, the capture path, or the privacy promise.

## Release

See `BUILD-IOS.md` for the full procedure. In short: bump `MARKETING_VERSION`
and `CURRENT_PROJECT_VERSION` on **all three** targets, deploy the CloudKit
schema to Production if and only if the SwiftData model changed (new keys
inside the `humanTagsData` JSON need no deploy), archive for Any iOS Device,
upload, write What's New in every language in
`fastlane/metadata/*/release_notes.txt`, run `tools/fastlane.sh metadata
version:X.Y`, then submit in App Store Connect.

`fastlane/metadata/` is the single source of truth for the listing text;
`APPSTORE.md` keeps only what fastlane doesn't cover. No lane uploads a build
or submits for review.

Every release also updates the website feature list, the press page fact
sheet (version and date) and, if images changed, the press kit
(`tools/make-presskit.sh`). Remind the owner to file a Featuring Nomination in
App Store Connect a few weeks before any notable release. Details:
`BUILD-IOS.md` → "Promotion, every release".
