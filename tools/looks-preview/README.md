# Looks preview

Review the camera colour looks on real photos **without the app or a device**.
It compiles the actual engine (`ARCHIve/ARCHIve/Camera/CameraProcessing.swift`)
and renders every look on a folder of photos into one contact sheet
(rows = photos, columns = looks).

## Use

```bash
# 1. Put a few photos in the samples folder (JPG / PNG / HEIC — straight off the iPhone is fine)
open tools/looks-preview/samples

# 2. Render + open the contact sheet
bash tools/looks-preview/preview.sh

# …or point it at any folder:
bash tools/looks-preview/preview.sh ~/Desktop/test-shots
```

Output: `<folder>/_looks-preview.png`.

Because it uses the real engine, what you see is exactly what the app produces
(grain included — the live preview omits grain, but captured photos and these
previews show it). Best reviewed with a mix of light: a sunny shot, an overcast
one, and a night/neon one, so the day looks and the night looks (CineStill,
Eterna) each get a fair frame.

To change a look, edit `CameraProcessing.swift` and re-run — no Xcode needed.
