# App Store listing: Archipic

**The listing text lives in [`fastlane/metadata/`](fastlane/metadata/).** That is
the single source of truth for the name, subtitle, keywords, description,
promotional text, What's New, categories and URLs. Edit the files there and
upload with `tools/fastlane.sh` (see [`fastlane/README.md`](fastlane/README.md)).
Don't copy that text back into this file.

This file keeps only what fastlane doesn't handle: fixed identity fields, the
App Privacy and age rating answers, screenshot sizes, App Review notes, the
archive of past What's New texts, and checklists.

---

## Identity (set once in App Store Connect)

| Field | Value |
| --- | --- |
| **Bundle ID** | com.samiabdulnour.archive |
| **Apple ID** | 6777989742 |
| **SKU** | archive-ios-001 |
| **Age rating** | 4+ |
| **Price** | Free |

Support and privacy URLs are required by App Store Connect, so
`docs/support.html` and `docs/privacy.html` must always stay reachable.

---

## App Privacy (App Store Connect questionnaire)

Answer: **Data Not Collected.**
- The developer collects nothing. Photos, tags and location stay on the device
  and sync only to the **user's own private iCloud** (CloudKit private database),
  which is not "collection by the developer."
- Not used for tracking. No third-party SDKs/analytics.
- (The bundled `PrivacyInfo.xcprivacy` already declares the one required-reason
  API: UserDefaults, reason CA92.1.)

---

## Age rating
Run the questionnaire; everything is "None" → **4+**.

---

## Screenshots (required sizes)

Apple requires **6.9" iPhone** screenshots (e.g. iPhone 16 Pro Max,
**1320 × 2868 px**). A 6.5" set (1242 × 2688) is optional but nice.

**New in 1.4 — iPad screenshots are now required.** Because the app is now
universal, App Store Connect won't let you submit without an **iPad 13"** set
(**2064 × 2752 px**, portrait). Two or three is enough — show the split view
(sidebar + grid) and the two-pane Board composer; they're the reason to be on
iPad. Capture from an iPad simulator the same way.

Capture in the Simulator (**Device → … → Screenshots**, or ⌘S) or AirDrop from
your phone. Suggested iPhone set (6):

1. **Camera viewfinder** — aspect guide, level, mode pill. → "Capture in ten seconds."
2. **Tagging** — Building → Typology/Room tiles mid-tag. → "Two taps. Filed."
3. **Gallery — Time** — the grid (try 3-up). → "Your whole archive, by time."
4. **Reference lens** — rows by typology/element with counts. → "Browse by what it is."
5. **Map lens** — pins across a map. → "Find it by place."
6. **Photo detail** — image + tag rows (+ a rating). → "Private. Synced. Yours."

(Captions are optional overlays you'd add when composing the screenshots; App
Store Connect itself doesn't take captions.)

Upload with `tools/fastlane.sh screenshots` (reads `AppStoreScreenshots/Framed/` and
`AppStoreScreenshots/iPad-13-gallery.png`).

---

## App Review Information (private)

| Field | Value |
| --- | --- |
| Contact name | Sami Abdulnour |
| Contact email | _your email_ |
| Contact phone | _your phone_ |
| Sign-in required? | No (no account) |
| Demo account | n/a |

**Notes to reviewer:**

Archipic is a single-user, on-device photo journal built in native SwiftUI.
There is no login or account. Photos and tags are stored locally with SwiftData
and synced only to the user's own private iCloud (CloudKit private database) —
no developer server, no analytics, no third-party SDKs. The map uses Apple
MapKit. Camera and location permissions are used only while the user is actively
capturing a photo (location is stored on the photo to enable the Map view).

---

## What's New archive (shipped versions)

The text for the *next* version goes in `fastlane/metadata/*/release_notes.txt`.
After a release, copy it here under its version number.

### 1.4 (28 September 2026)

Archipic comes to iPad, opens up to the rest of your apps, and gets quicker to
file.

NOW ON IPAD
A proper big-screen archive. The four lenses move into a sidebar, the grid fills
the page, and the Board composer becomes two panes — your photos on one side, a
live poster preview on the other. Portrait and landscape.

SAVE FROM THE SHARE SHEET
A façade in your camera roll, a plan someone sent you, a screenshot you grabbed?
Share the image straight to Archipic, pick Building, Element or Graphic, and it's
filed — ready to finish tagging later.

CAPTURE WITHOUT OPENING THE APP
A new "Capture in Archipic" action for Shortcuts, Siri and the Action Button.
Hold the button and you're in the viewfinder — optionally filing straight into a
named project.

FIND ANY TAG BY NAME
Not sure which category a fence lives under? Tap the new search button and type
it — Archipic jumps straight to the tag, wherever it's filed, so the vocabulary
that makes your archive searchable stays consistent.

SUGGESTIONS FROM THE PHOTO
Photograph a book page or a wall label and Archipic reads it on-device, offering
the title, author and year for one-tap confirmation. Nothing leaves your phone.

YOUR TAGS TRAVEL
Shared photos now carry their tags as standard metadata — keywords, caption,
title and rating — so they open correctly in Lightroom, Bridge and InDesign.
Keep or strip the location per share.

SHAREABLE BOARDS
Export a Board as a square, portrait or story image, not just a PDF — ready to
post.

Plus a smoother camera level, faster capture, and fixes throughout.

### 1.3

Video comes to Archipic — plus a visual refresh and a lot of polish.

VIDEO
Capture video as easily as stills. Switch the camera between Photo and Video,
record in clean HD, and your clips file, browse, share, and land on Boards right
alongside your photos — cropped to the same framing you shot.

A NEW MARK
A new icon — a filled disc inside a technical dash-dot ring — now runs through
the whole app. It's the shutter you tap, and it spins while a video records. The
Home Screen, Lock Screen, and Control Centre widgets wear it too.

ONE CAMERA
Reference and Project capture are now a single, calmer viewfinder: your project
sits top-left, tilt correction top-right, and the film looks are one tap away —
with the frame holding its exact size as you choose.

COLOUR, REWORKED
The film looks were rebuilt from measured colour — natural skin tones across the
set, and a proper Eterna: green-shadowed and moody, with crisp, saturated neons.

BOARDS
Compose any selection into a print-ready poster — a justified gallery wall — or
an A4 journal, exported as PDF.

A SMOOTHER GALLERY
Thumbnails fade in like the native Photos grid instead of blinking, filters
animate cleanly, and the grid remembers your preferred photos-per-row.

And dozens of fixes across video recording, capture speed, and stability.

### 1.0 (11 June 2026)

First release. Fast two-tap capture, the architecture tag taxonomy
(Building / Element / Graphic), a native camera, gallery browsing by time,
reference, project and place, search and filters, favourites and ratings,
and private iCloud sync.

---

## Pre-submit checklist: Version 1.4 (shipped)

**Version bump (do it on BOTH targets — app + widget):**
- [ ] `MARKETING_VERSION` 1.3 → **1.4**
- [ ] `CURRENT_PROJECT_VERSION` 5 → **7** (build 6 was uploaded but never submitted; 7 adds the
      camera orientation, zoom readout and project rename/delete fixes)

**Listing:**
- [ ] Paste the **Version 1.4 — What's New** (above) into App Store Connect.
- [ ] Update the **Description**, **Promotional text** and **Keywords** (above).
- [ ] Confirm the store **name is "Archipic"** (renamed from Archi.vé — same
      bundle id, so this is an update, not a new app).
- [ ] **iPad 13" screenshots** (2064 × 2752) — now required, plus the 6.9"
      iPhone set.

**Build / data:**
- [ ] **CloudKit schema deploy — most likely NOT needed.** 1.4 added no new
      SwiftData columns (new tag data lives inside the `humanTagsData` JSON; the
      Share extension writes photos through the existing `Photo` model). Confirm
      the model is unchanged since 1.3; deploy to Production only if it changed.
- [ ] App Privacy answers are **unchanged — still "Data Not Collected"** (no
      analytics or SDKs added; OCR runs on-device, exports and Shortcuts are
      local).

**Standing (unchanged from before):**
- [ ] Privacy Policy URL + Support URL reachable (archi-ve.app at the time; it now forwards to archipic.app).

For every release from 1.5 on, follow `BUILD-IOS.md` (steps 1–6 and
"Promotion, every release") instead of a per-version checklist here.
- [ ] Contact email/phone filled in App Review Information.
