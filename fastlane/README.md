# fastlane: the App Store listing as code

The App Store listing text lives in `fastlane/metadata/`, one plain text file per
field. You edit the files and run one command to send them to App Store Connect,
so you never have to open App Store Connect to change marketing text.

fastlane is developer tooling only. It runs on your Mac and is never part of the
app. It's a Ruby program, pinned to one exact version by `Gemfile.lock`, and
installed into `vendor/bundle/` (git-ignored) the first time you run it.

Always run it through the wrapper, which picks the right Ruby and settings:

```
tools/fastlane.sh <lane>
```

## Lanes

| Lane | What it does | When it works |
| --- | --- | --- |
| `metadata` | Uploads every text file in `fastlane/metadata/`. Never uploads a build, never uploads screenshots, never submits. | When a version is in "Prepare for Submission". Add `version:1.5` to create that version if it doesn't exist yet. |
| `promo_text` | Uploads only `promotional_text.txt` (each language). | Any time. Apple allows promotional text to change on the live version, without a new release. This is the place for launch messaging. |
| `screenshots` | Replaces the screenshots with `AppStoreScreenshots/Framed/*.png` (iPhone 6.9") and `AppStoreScreenshots/iPad-13-gallery.png` (iPad 13"). | When a version is in "Prepare for Submission". |
| `download_metadata` | Pulls the live listing into `fastlane/metadata/`, overwriting the local files. Commit first, then `git diff` to see what differs. | Any time. |

Which fields need a new version: name, subtitle, keywords, description, What's
New, categories and the support and marketing URLs only change together with a
new version. Promotional text can change any time.

## Files

```
fastlane/
  Appfile                 the app's bundle ID
  Fastfile                the lanes above
  metadata/
    primary_category.txt  e.g. PHOTO_AND_VIDEO
    secondary_category.txt
    en-US/
      name.txt            30 characters max
      subtitle.txt        30 characters max
      keywords.txt        100 characters max, commas, no spaces
      description.txt     4000 characters max
      promotional_text.txt  170 characters max
      release_notes.txt   What's New for the next version
      support_url.txt, marketing_url.txt, privacy_url.txt
```

A field with no file is left alone on upload.

## One-time setup: the App Store Connect API key

fastlane signs in with an API key instead of your Apple ID, so it never needs
your password or a two-factor code.

1. In App Store Connect: **Users and Access → Integrations → App Store Connect
   API → Team Keys → Generate API Key** (the + button). Name it `fastlane`,
   access **App Manager**.
2. Download the key file `AuthKey_XXXXXXXXXX.p8`. Apple lets you download it
   **once**, so keep it safe. Note the **Key ID** (next to the key) and the
   **Issuer ID** (above the list).
3. Move it outside this repository and make it readable only by you:

   ```
   mkdir -p ~/.appstoreconnect
   mv ~/Downloads/AuthKey_*.p8 ~/.appstoreconnect/
   chmod 600 ~/.appstoreconnect/AuthKey_*.p8
   ```

4. Create `~/.appstoreconnect/archipic.env` with these three lines (your values):

   ```
   export APP_STORE_CONNECT_API_KEY_KEY_ID=XXXXXXXXXX
   export APP_STORE_CONNECT_API_KEY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   export APP_STORE_CONNECT_API_KEY_KEY_FILEPATH=$HOME/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
   ```

   `tools/fastlane.sh` reads this file on every run. The key itself is never
   printed or logged.
5. Check it works and that the repo matches the store:

   ```
   tools/fastlane.sh download_metadata
   git diff fastlane/metadata
   ```

## Safety rails

- `.gitignore` blocks `*.p8`, `AuthKey_*` and `*api_key*.json`, so a key can't
  be committed by accident.
- App Review contact details (name, email, phone) are deleted after
  `download_metadata` and are git-ignored too. This repository is public. Keep
  them in App Store Connect only.
- Usage statistics to fastlane are switched off (`opt_out_usage`), in keeping
  with the app's privacy promise.
- No lane can upload a build, submit for review or release. Those stay manual.
