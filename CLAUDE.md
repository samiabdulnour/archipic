# archi-archive

A personal, private photo-journal app for an architect. The owner takes photos from everyday life that relate to their architectural work — site visits, references spotted in the world, exhibitions, details, whatever catches the eye — tags them with a small structured vocabulary, and browses them later by tag.

## ⚠️ DIRECTION CHANGE — native-first for the App Store (owner directive, 2026-06-01)

**The goal is now a high-quality, fully functional native iPhone app shipped to the App Store. The web app and GitHub Pages deployment are NO LONGER a target.** The owner explicitly lifted the constraints that were limiting app quality: the "no native iOS Swift", "plain HTML/CSS/JS only", "one or two files", and "web app is the canonical source / Capacitor syncs from it" rules below are **superseded**. Build the app in whatever interface/stack best serves quality and the native iOS experience, even if it means substantially more work (e.g. native AVFoundation camera for real flash/focus/exposure, native UI screens, native storage).

The product intent is unchanged — fast capture, structured two-tap tagging, the Kind/Context-derived taxonomy (see below), reliable local storage, browse-by-tag, separate `tags_human` / `tags_machine` fields. Only the *implementation constraints* are relaxed. The exact target architecture (full native rewrite vs. incremental native migration from the existing Capacitor/web build) is being decided with the owner; older sections of this file describe the previous web-only design and remain as reference for the existing behavior to preserve.

## Who this is for

A single user (the owner) on their own iPhone. Not multi-user. Not public. No accounts, no sharing, no cloud sync in early stages.

## Goals

- **Capture fast.** Open app, tap one button, take photo, tag in 2 taps, done. The whole flow should take under 10 seconds so it's usable while walking.
- **Structured tags, not free text.** Tags are pre-defined buttons, not a keyboard field. Typing on a phone while standing on a sidewalk is the enemy.
- **Reliable local storage.** Photos must survive closing Safari/Chrome and reopening days later. IndexedDB.
- **Browse by tag.** Later, filter the archive by any tag or combination.
- **Open door to image-recognition assistance.** The data model keeps human tags and future machine-suggested tags as separate fields from day one, so adding auto-suggest later is a small change, not a refactor.

## Scope — in

- Camera capture via `<input type="file" capture="environment">` or `getUserMedia`.
- Tag flow: a short sequence of binary/multi-choice buttons after each photo.
- Local persistence (IndexedDB) for photos + tags.
- Gallery view with tag filters (later stage).
- Voice notes attached to a photo (later stage, optional).
- Progressive Web App so it installs to the home screen (last stage).

## Scope — out (for now)

- Cloud sync, multi-device, sharing, accounts, login.
- Editing photos (crop, filter, rotate).
- Any backend server. The app is 100% client-side.

## iOS app (in scope as of 2026-05-24)

The app is also shipped to the App Store as a native iOS app via **Capacitor** — a thin wrapper around the same `index.html`, not a rewrite. Bundle ID: `com.samiabdulnour.archive`. App name: Archi.vé. See `BUILD-IOS.md` for the step-by-step build, and `APPSTORE.md` for listing copy + screenshots. Web app at `samiabdulnour.github.io/archi-ve/` stays the canonical source; Capacitor syncs from it.

Do not add native iOS Swift code, Cordova plugins, or fork the codebase. Anything iOS-specific lives in `capacitor.config.json`, `BUILD-IOS.md`, or — at submission time — the auto-generated `/ios` Xcode project (which is committed but never hand-edited).

**Documented exception (owner-approved 2026-06-01):** one piece of hand-written native Swift is allowed — `ios/App/App/NativeMotion.swift` (a small CoreMotion plugin + a `MotionBridgeViewController`). It exists because the web DeviceMotion API inside WKWebView only delivers after a user tap, which left the camera level/icon-spin frozen on launch; CoreMotion gravity needs no permission or gesture. Do NOT delete it as part of "no native Swift" cleanup. It is wired via `Main.storyboard` (custom class `MotionBridgeViewController`) and registered in `App.xcodeproj/project.pbxproj` — these three edits to the otherwise-generated `/ios` project must be preserved across any `cap` regeneration. See memory `ios-device-motion`.

## Target platforms

- **Primary:** iPhone Safari.
- **Secondary:** iPhone Chrome.
- Desktop browsers only need to work well enough for development/debugging.

## Tag vocabulary

Grounded in a manual scan of the owner's actual camera roll (2022–2026). After each photo, the user answers two questions, always the same two:

### Tap 1 — **Kind** (what is the photo of?)
- **Space** — a 3D thing you stood in or in front of: building, interior, plaza, ruin, installation.
- **Surface** — a close-up of material or detail: facade, texture, tile, joint, carving.
- **Page** — something flat with information: book spread, drawing, sketch, artwork on a wall, printed document.

### Tap 2 — **Context** (what was the situation?)
- **Travel** — encountered out there on a trip, not tied to your own work (heritage sites, cities, buildings elsewhere).
- **Exhibition** — at a biennale, gallery, museum, architecture show. Includes artworks on gallery walls.
- **Making** — your own fabrication/installation/project in progress.
- **Reference** — book page, printed drawing, article, study material.

**3 × 4 = 12 coordinates.** Two taps per photo.

### Data model note

Every photo record has two tag fields:
- `tags_human` — the user's own Kind + Context answers above.
- `tags_machine` — reserved for future image-recognition suggestions. Empty for now. Do not merge these two fields — keep them separate so human intent and machine guesses stay distinguishable forever.

Place (GPS) and time (timestamp) come free from the phone — do not tag them manually. Project association is handled later via an editable project list, not a fixed value in these taps.

### Scope deferred

- **Artworks in museums** are in scope — they map to `Page/Exhibition` or `Space/Exhibition`.
- **Screenshots** (digital content saved from the phone) are a big part of how the owner archives today, but this app only accepts camera captures in Stage 1–3. Revisit after the core loop works.

## Technical constraints

- **Stack: plain HTML, CSS, JavaScript.** No React, Vue, Svelte, TypeScript, build tools, bundlers, or npm dependencies unless there's a concrete reason the plain approach doesn't work. The owner is learning to code through this project — readable > clever.
- **One or two files** in the early stages. Split into more files only when size genuinely demands it.
- **No frameworks for storage** — use the browser's IndexedDB directly (a thin wrapper function is fine).
- **No external fonts or CDNs** unless necessary. The app should work offline eventually.

## How to collaborate with the owner

- The owner is a complete beginner to programming. Explain what code does when adding non-trivial chunks.
- Prefer small, working increments over big leaps.
- Before adding a new dependency or pattern, explain the tradeoff and ask.
- When the owner describes a bug, they describe the *symptom* — debug from that, don't assume.
- Commit to git at the end of each working stage with a clear message.
- **Auto-merge policy (owner preference, 2026-05-24):** when Claude pushes a PR for changes Claude wrote, Claude squash-merges it directly into `main` without waiting for manual review. The owner reviews on the live site after GitHub Pages rebuilds (~1–3 min). This means: be conservative about what you push — no speculative refactors, no breaking changes to the IndexedDB schema or `archi-archive:*` localStorage keys without explicit confirmation. Anything that touches data integrity, capture flow, or could lose photos still requires asking first.

## Current stage

**Stages 1–4 shipped.** Capture loop, tag taxonomy, gallery with lens/sub-tab filters, light + dark themes. Web app live at `samiabdulnour.github.io/archi-ve/`.

**Next:** App Store submission via Capacitor. Web codebase is feature-stable; the iOS prep (manifest, icons, capacitor.config, BUILD-IOS.md, APPSTORE.md) is in place. Owner is waiting on Apple Developer Program enrolment approval, then will build on their Mac per `BUILD-IOS.md`.
