# Building Archipic for the App Store (native SwiftUI)

The app is a native SwiftUI / SwiftData project at `Archipic/Archipic.xcodeproj`.
Bundle ID: `com.samiabdulnour.archive` · Team: `N6QDF49V2G`

---

## Updating and uploading a new build

1. **Bump the version numbers** in `Archipic/Archipic.xcodeproj/project.pbxproj`
   (or via Xcode → target General tab):
   - `MARKETING_VERSION` — the user-visible version string (e.g. `1.1`).
     Must be higher than the currently live App Store version to create a new
     release.
   - `CURRENT_PROJECT_VERSION` — the build number (integer, e.g. `4`).
     Must be strictly higher than any build already uploaded to App Store
     Connect (including rejected or expired builds).
   - Set the **same** values on **all three** targets: `Archipic`,
     `ArchipicWidgetsExtension` and `ShareExtension`. App Store Connect rejects uploads where the
     extension build number doesn't match the app.

2. **Deploy the CloudKit schema** — *only if the SwiftData model changed since
   the last release.*
   CloudKit Console → the app's container → **Schema** → **Deploy Schema
   Changes…** (Development → Production).
   Adding new fields is safe and additive; the live app ignores fields it
   doesn't know about. (New keys inside the `humanTagsData` JSON blob need
   **no** deploy — that field already exists in Production.)

3. **Archive (Release build).** In Xcode:
   - Set the run destination to **Any iOS Device (arm64)**.
   - **Product → Archive** and wait for the build to finish.

   Or via the CLI:
   ```bash
   xcodebuild -project Archipic/Archipic.xcodeproj -scheme Archipic \
     -configuration Release \
     -destination 'generic/platform=iOS' \
     -archivePath build/Archive.xcarchive \
     -allowProvisioningUpdates archive
   ```

4. **Upload.** Window → Organizer → pick the new archive →
   **Distribute App → App Store Connect → Upload**.
   Apple processes the build in ~10–30 minutes.

5. **Listing text.** Write What's New for this version, in the house style
   (see below), into `fastlane/metadata/*/release_notes.txt`, **every
   language** (en-US, en-GB, en-AU, cs). Then check and upload:
   ```bash
   python3 tools/check-listing.py
   tools/fastlane.sh metadata version:1.5     # the MARKETING_VERSION
   ```
   This creates the version in App Store Connect if needed and uploads name,
   subtitle, keywords, description, What's New, promotional text, categories
   and URLs. It never uploads a build or submits. First-time setup:
   `fastlane/README.md`.

6. **Submit.** App Store Connect → the version → attach the processed build →
   **Add for Review → Submit for Review**. This stays a manual click.

Review usually takes 1–3 days. SwiftData / CloudKit stores survive updates —
the owner's photos and tags are preserved across upgrades.

---

## Promotion, every release

The app, the store listing and the website do the promoting, so each release
updates all three. In order:

1. **What's New** in every language (step 5 above), in the house style:
   - No em-dashes or en-dashes joining clauses. A comma, a full stop or
     brackets instead.
   - Describe, don't praise. Facts: what it does, how, what it doesn't do.
   - Banned: revolutionary, unique, seamless, cutting-edge, game-changer,
     next-level, powerful, effortless, "you deserve", "it's not just X,
     it's Y", tidy rule-of-three adjective lists, empty closing summaries.
   - No exclamation marks, no emoji. British spelling (colour, favourites).
   - Every claim true of the shipped build.
   `tools/check-listing.py` catches the dashes and Apple's length limits.
2. **Website.** Add any new feature to `docs/index.html`, briefly. On
   `docs/press.html`, update **Current version** and its date in the fact
   sheet. Then:
   ```bash
   tools/make-presskit.sh                 # if the icon or screenshots changed
   python3 tools/check-site-links.py      # merging to main deploys the site
   ```
3. **Screenshots**, if the UI changed visibly: update
   `AppStoreScreenshots/Framed/` and `AppStoreScreenshots/iPad-13-gallery.png`,
   then `tools/fastlane.sh screenshots`, `tools/make-presskit.sh`, and
   `swift tools/og-card/make-og.swift` (the link preview card).
4. **After it's live:** copy this version's en-US What's New into the archive
   in `APPSTORE.md`. Launch messaging can go in promotional text at any time,
   no release needed: edit `promotional_text.txt`, then
   `tools/fastlane.sh promo_text`.
5. **[owner] Featuring Nomination**, a few weeks before any notable release:
   App Store Connect → the app → **Featuring Nominations** → describe what's
   new and why it matters. Apple asks for this ahead of the release date.

---

## Screenshots

The App Store set is `AppStoreScreenshots/Framed/*.png` (iPhone 6.9",
1320×2868) plus `AppStoreScreenshots/iPad-13-gallery.png` (iPad 13",
2064×2752). Upload both with:

```bash
tools/fastlane.sh screenshots
```

(These two are not committed to git; they live on the owner's Mac.)
`AppStoreScreenshots/gen_screenshots.py` regenerates the older unframed set.

---

## Website and domain

`docs/` is served by GitHub Pages from `main`, at the domain in `docs/CNAME`
(currently **archi-ve.app**). Merging to `main` deploys it within a minute or
two. App Store Connect requires `support.html` and `privacy.html` to stay
reachable.

### Moving to archipic.app (bought October 2026, not yet live)

archipic.app is the long-term domain, and Board exports already print it. **Do
not ship a release containing the Board mark until archipic.app answers.**
The old address must keep working for a while, because the live listing links
to `archi-ve.app/support.html` and `archi-ve.app/privacy.html`. Order:

1. **[owner] DNS for archipic.app** at the registrar: `A` records to GitHub
   Pages (185.199.108.153, 185.199.109.153, 185.199.110.153,
   185.199.111.153), the matching `AAAA` records (2606:50c0:8000::153 to
   2606:50c0:8003::153), and `www` as a `CNAME` to `samiabdulnour.github.io`.
2. **Switch the site:** change `docs/CNAME` to `archipic.app` and replace
   `archi-ve.app` with `archipic.app` everywhere it's hard-coded
   (`grep -rn "archi-ve\.app" docs tools fastlane/metadata CLAUDE.md APPSTORE.md BUILD-IOS.md`):
   the `og:url` / `og:image` tags, the press page, the link checker's `SITE`,
   and every `fastlane/metadata/*/*_url.txt`. Merge, then in GitHub →
   Settings → Pages confirm the custom domain and tick **Enforce HTTPS** once
   the certificate is issued.
3. **[owner] Keep archi-ve.app alive** as a permanent redirect (HTTP 301)
   that keeps the path, so `/support.html` and `/privacy.html` still land.
   GitHub Pages serves one domain per repository, so do this with the
   registrar's URL forwarding (forward with path) rather than GitHub.
4. **Listing URLs:** the privacy policy URL can be changed in App Store
   Connect at any time. The support and marketing URLs change with the next
   version's `tools/fastlane.sh metadata`.
5. Once the listing no longer points at archi-ve.app, the redirect can stay
   indefinitely at the cost of the domain renewal. Links in old posts, emails
   and printed matter keep working as long as it does.
