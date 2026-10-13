#!/bin/zsh
# Builds the press kit served at archipic.app/press.html.
#
# Run from anywhere, on the Mac (it uses sips, which ships with macOS):
#   tools/make-presskit.sh
#
# Inputs (local files, not all in git):
#   Archipic/Archipic/Assets.xcassets/AppIcon.appiconset/AppIcon.png   the app icon
#   AppStoreScreenshots/Framed/*.png       iPhone screenshots, as on the App Store
#   AppStoreScreenshots/iPad-13-gallery.png   iPad screenshot
#   AppStoreScreenshots/Boards/*           optional: example Board exports (jpg/png/pdf)
#
# Output, in docs/press/:
#   full-size files a journalist can download one at a time,
#   thumbs/ small previews the press page shows,
#   archipic-presskit.zip with every full-size file.
#
# Screenshots are saved as high-quality JPEG at their original size, which keeps
# the kit a few MB instead of 15. File dates inside the zip are fixed, so
# re-running with unchanged inputs produces an identical zip (no git churn).
set -euo pipefail

ROOT="${0:A:h:h}"
SRC_ICON="$ROOT/Archipic/Archipic/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SRC_SHOTS="$ROOT/AppStoreScreenshots/Framed"
SRC_IPAD="$ROOT/AppStoreScreenshots/iPad-13-gallery.png"
SRC_BOARDS="$ROOT/AppStoreScreenshots/Boards"
OUT="$ROOT/docs/press"
STAMP="202601010000"            # fixed file date for a reproducible zip

for f in "$SRC_ICON" "$SRC_IPAD"; do
  [[ -f "$f" ]] || { echo "Missing $f" >&2; exit 1; }
done
[[ -d "$SRC_SHOTS" ]] || { echo "Missing $SRC_SHOTS" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/thumbs"

jpeg() {   # jpeg <source> <dest.jpg>
  sips -s format jpeg -s formatOptions 90 "$1" --out "$2" >/dev/null
}
thumb() {  # thumb <source> <dest.jpg>   (480 px on the long side)
  sips -Z 480 -s format jpeg -s formatOptions 80 "$1" --out "$2" >/dev/null
}

cp "$SRC_ICON" "$OUT/archipic-icon-1024.png"
thumb "$SRC_ICON" "$OUT/thumbs/archipic-icon-1024.jpg"

for f in "$SRC_SHOTS"/*.png(N); do
  name="iphone-${f:t:r}"
  jpeg "$f" "$OUT/$name.jpg"
  thumb "$f" "$OUT/thumbs/$name.jpg"
done

jpeg "$SRC_IPAD" "$OUT/ipad-gallery.jpg"
thumb "$SRC_IPAD" "$OUT/thumbs/ipad-gallery.jpg"

if [[ -d "$SRC_BOARDS" ]]; then
  for f in "$SRC_BOARDS"/*.(jpg|jpeg|png|pdf)(N); do
    cp "$f" "$OUT/board-${f:t}"
    [[ "${f:e}" == "pdf" ]] || thumb "$f" "$OUT/thumbs/board-${f:t:r}.jpg"
  done
else
  echo "Note: no example Boards yet (put 2 or 3 exports in AppStoreScreenshots/Boards/)."
fi

# Zip every full-size file, in a stable order, with fixed dates.
cd "$OUT"
files=( *.(png|jpg|pdf)(N) )
touch -t "$STAMP" "${files[@]}"
zip -X -q archipic-presskit.zip "${files[@]}"
touch -t "$STAMP" archipic-presskit.zip

echo "Press kit in docs/press/:"
ls -la "$OUT" | awk 'NR>1 {print "  " $5 "\t" $9}'
