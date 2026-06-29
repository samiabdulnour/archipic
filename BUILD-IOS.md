# Building Archi.vé for the App Store (native SwiftUI)

The app is a native SwiftUI / SwiftData project at `ARCHIve/ARCHIve.xcodeproj`.
Bundle ID: `com.samiabdulnour.archive` · Team: `N6QDF49V2G`

---

## Updating and uploading a new build

1. **Bump the version numbers** in `ARCHIve/ARCHIve.xcodeproj/project.pbxproj`
   (or via Xcode → target General tab):
   - `MARKETING_VERSION` — the user-visible version string (e.g. `1.1`).
     Must be higher than the currently live App Store version to create a new
     release.
   - `CURRENT_PROJECT_VERSION` — the build number (integer, e.g. `4`).
     Must be strictly higher than any build already uploaded to App Store
     Connect (including rejected or expired builds).
   - Set the **same** values on **both** targets: `ARCHIve` and
     `ArchiveWidgetsExtension`. App Store Connect rejects uploads where the
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
   xcodebuild -project ARCHIve/ARCHIve.xcodeproj -scheme ARCHIve \
     -configuration Release \
     -destination 'generic/platform=iOS' \
     -archivePath build/Archive.xcarchive \
     -allowProvisioningUpdates archive
   ```

4. **Upload.** Window → Organizer → pick the new archive →
   **Distribute App → App Store Connect → Upload**.
   Apple processes the build in ~10–30 minutes.

5. **Submit.** App Store Connect → your app → **(+) version** (the
   `MARKETING_VERSION` string) → write **What's New** → attach the processed
   build → **Add for Review → Submit for Review**.

Review usually takes 1–3 days. SwiftData / CloudKit stores survive updates —
the owner's photos and tags are preserved across upgrades.

---

## Screenshots

Five designed 1320×2868 px screenshots live in `AppStoreScreenshots/`.
Regenerate any time:

```bash
python3 AppStoreScreenshots/gen_screenshots.py
```

Upload them under the **6.9" (iPhone 17 Pro Max)** slot in App Store Connect.
Apple scales them down for older device sizes automatically.

---

## Privacy policy & support page

`docs/privacy.html` and `docs/support.html` are served via GitHub Pages at
`samiabdulnour.github.io/archi-ve/`. Those URLs are required by App Store
Connect in the app's metadata.
