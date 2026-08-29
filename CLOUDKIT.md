# CloudKit sync — how it works & release checklist

Archipic stores everything locally with **SwiftData**, and that store is
**mirrored to your private iCloud** so it syncs across your devices and is
backed up automatically.

- **Container:** `iCloud.com.samiabdulnour.archive`
- **Wiring:** `ModelContainer` uses `ModelConfiguration(cloudKitDatabase: .automatic)`
  (see `ARCHIve/ARCHIve/ARCHIveApp.swift`).
- **Entitlements:** `ARCHIve/ARCHIve/ARCHIve.entitlements` (iCloud container,
  CloudKit service, `aps-environment`) + `remote-notification` background mode.
- **Record type in CloudKit:** `CD_Photo` (SwiftData prefixes model names with
  `CD_`). Each photo's image/label become **CKAsset** fields.

Every user's data goes to **their own** private iCloud database. You (the
developer) can never see other users' photos — only your own dev account's
records appear in the Console.

---

## ⚠️ The one must-do before release: promote the schema to Production

CloudKit has **two separate environments**:

- **Development** — used by builds you run from Xcode. The schema (record types
  + fields) is **created automatically** the first time each field syncs.
- **Production** — used by **TestFlight and App Store** builds.

The schema you build up by running the app in Xcode lives **only in
Development**. If you ship to TestFlight/App Store without copying it to
Production, **sync silently fails for everyone** (the app still works locally,
but nothing syncs). So this step is mandatory before the first submission, and
again after any model change.

### Steps

1. **Generate the full schema in Development.** Run the app from Xcode on a real
   device and create at least one of *everything* so every field exists:
   - a **Building**, an **Element**, and a **Graphic** photo (covers the tag fields),
   - one with a **Captured label** (creates the label asset field),
   - one assigned to a **Project**,
   - one taken with **location on** (creates the lat/long fields).
   Open **Settings → iCloud sync** and confirm the account shows **Available**
   and Status reaches **Synced** — that means the records reached Development.

2. **Open the CloudKit Console:** https://icloud.developer.apple.com
   → sign in with the Apple ID for team **N6QDF49V2G**
   → choose the container **`iCloud.com.samiabdulnour.archive`**.

3. In **Development**, open **Schema → Record Types** and confirm `CD_Photo`
   exists with the expected fields (image asset, createdAt, latitude, longitude,
   humanTagsData, project, importedAt, labelImageData asset, etc.).

4. Click **Deploy Schema to Production** (top of the Schema page). Review the
   diff it shows and **confirm**.

5. Switch the Console's environment selector to **Production** and verify
   `CD_Photo` and its fields/indexes are now there.

That's it — TestFlight/App Store builds will now sync.

---

## After ANY future model change

Whenever you add or change a synced property on `Photo` (or add a new `@Model`):

1. Run from Xcode so the new field is created in **Development**.
2. **Deploy Schema to Production** again before the next release.

**Important CloudKit rule:** the Production schema is **additive-only** — you
**cannot delete or rename** existing fields/record types in Production. So:

- Only **add** new fields, and make them **optional / defaulted** (we already do
  this — see `Photo.swift`).
- **Never rename** an existing property; add a new one instead.
- Keep the "no `@Attribute(.unique)`" rule (CloudKit forbids unique constraints).

---

## Push environment (`aps-environment`)

The entitlements file sets `aps-environment = development`. You do **not** need
to change this by hand for release: with **Automatic** signing, Xcode swaps in
the **production** APS environment in the distribution provisioning profile when
you **Archive**. (Only if you ever switch to *manual* signing would you set
`aps-environment = production` for release builds.)

---

## Testing that sync actually works

- **Two devices, same Apple ID**, app installed on both → capture on one, it
  appears on the other. Give it a few seconds to minutes — CloudKit sync is
  *eventually consistent* and needs a network connection.
- **Settings → iCloud sync** shows: account availability, "Syncing…" while
  active, and "Synced <time ago>" when done.
- If the account reads **Not signed in**, sync is paused until the user signs
  into iCloud in iOS Settings.

---

## Gotchas / things to tell users

- Photos count against the **user's iCloud storage** quota (images can be large).
- **First sync after installing on a new device** can take a while for a big
  archive.
- Sync needs network; offline captures sync later automatically.
- The **manual backup** (Settings → Backup → "Back up all photos") still works
  independently as a portable, off-iCloud copy — good before reinstalls.

---

## Quick reference

| Item | Value |
|------|-------|
| iCloud container | `iCloud.com.samiabdulnour.archive` |
| Record type | `CD_Photo` |
| Team ID | `N6QDF49V2G` |
| Console | https://icloud.developer.apple.com |
| Code | `ARCHIveApp.swift`, `ARCHIve.entitlements` |
