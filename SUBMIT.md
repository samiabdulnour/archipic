# Archipic — App Store submission runbook

The app is **submission-ready**: it archives and signs for distribution, has the
app icon (light/dark/tinted), CloudKit entitlements, usage strings, and a
privacy manifest. What's left is the parts that need **your Apple ID** and your
clicks — Claude can't enter your credentials, accept Apple's agreements, or
press "Submit" for you.

Do these in order. Steps marked **[you]** require your login/decisions.

---

## 0. One-time account prep **[you]**

1. Confirm your **Apple Developer Program** membership is active (it is — the app
   already signs CloudKit). https://developer.apple.com/account
2. Sign the latest **agreements** in **App Store Connect → Business** (Paid/Free
   apps agreement) — review can't start until these are accepted.

## 1. Promote CloudKit schema to Production **[you]** ⚠️ required for sync

App Store builds use CloudKit **Production**; your schema currently lives in
**Development**. Follow **`CLOUDKIT.md`** → "Deploy Schema to Production".
Quick version:
- Run the app, create one of each: a Building, Element, Graphic, one with a
  captured label, one with a project, one with location on (so every field
  exists in Development).
- https://icloud.developer.apple.com → container `iCloud.com.samiabdulnour.archive`
  → **Schema → Deploy Schema Changes… → Deploy to Production** → verify in
  Production.

If you skip this, the app works locally but **sync silently fails** for users.

## 2. Create the app record in App Store Connect **[you]**

https://appstoreconnect.apple.com → **Apps → +**
- Platform: iOS
- Name: **Archipic** (must be unique App Store-wide — have a backup like
  "Archipic Journal" in case it's taken)
- Primary language, Bundle ID: **com.samiabdulnour.archive**, SKU: e.g. `archive-001`.

## 3. Archive & upload the build

Recommended (GUI, easiest):
1. Open `ARCHIve/ARCHIve.xcodeproj` in **Xcode**.
2. Top bar device selector → **Any iOS Device (arm64)**.
3. **Product → Archive**. (Already verified to succeed from the command line.)
4. In **Organizer** → select the archive → **Distribute App → App Store Connect
   → Upload** → keep defaults (automatic signing) → **Upload**.
5. Wait for "processing" to finish in App Store Connect (a few–30 min); you'll
   get an email when the build is ready.

Bump versions for later releases: `MARKETING_VERSION` (e.g. 1.0 → 1.1) and
`CURRENT_PROJECT_VERSION` (build number, must increase every upload).

## 4. Fill the listing **[you]**

In App Store Connect, the app's **1.0** version page:
- **Screenshots** — required: 6.9" iPhone (e.g. iPhone 16 Pro Max) and 6.5".
  Capture from your device or simulator (camera, tagging, gallery, reference,
  detail). I can help script/organise these.
- **Description, keywords, promotional text** — see `APPSTORE.md` for draft copy
  (update if needed).
- **Support URL** (required) and optional Marketing URL.
- **Category**: Photo & Video (primary); Productivity (secondary).
- **Age rating**: fill the questionnaire (all "none" → 4+).

## 5. App Privacy **[you]**

App Store Connect → **App Privacy**. Archipic is private:
- **Data collection: None.** Photos and tags stay on device and sync to the
  user's **own** iCloud (CloudKit private database) — that is *not* "data
  collected by the developer." You can answer **"Data Not Collected."**
- Not used for tracking.
(The in-app `PrivacyInfo.xcprivacy` already declares the UserDefaults reason.)

## 6. Attach build, submit **[you]**

- On the 1.0 page → **Build → +** → pick the uploaded build.
- Export compliance: the app uses only standard encryption (HTTPS/iCloud) →
  answer the encryption question accordingly (typically "exempt"; confirm).
- **Add for Review → Submit**.

## 7. (Optional) TestFlight first — recommended

Before public release, install via **TestFlight** on your own device to test the
production build + production CloudKit end-to-end. App Store Connect →
**TestFlight** → add yourself as an internal tester.

---

## Pre-submit checklist

- [ ] Developer agreements signed
- [ ] CloudKit schema deployed to **Production**
- [ ] App record created (bundle `com.samiabdulnour.archive`)
- [ ] Archive uploaded, finished processing
- [ ] Screenshots (6.9" + 6.5"), description, keywords, support URL
- [ ] Category + age rating
- [ ] App Privacy = Data Not Collected
- [ ] Build attached, export compliance answered
- [ ] Submitted for review

## What Claude can still help with
- Drafting/refreshing `APPSTORE.md` copy (description, keywords, what's-new).
- Organising/renaming screenshots, writing a capture checklist.
- Version/build bumps and re-archiving for future updates.
- Debugging any validation errors Apple returns on upload.
