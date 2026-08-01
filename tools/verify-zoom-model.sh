#!/bin/bash
# Verify the camera's multi-lens zoom math (CameraZoom.model) against every
# iPhone rear-camera layout — offline, no device needed. It extracts the ACTUAL
# CameraZoom enum from CameraController.swift (so it can't drift from the app)
# and checks the computed lens stops against the buttons Apple's Camera shows.
#
# Run from the repo root:  bash tools/verify-zoom-model.sh
set -euo pipefail
SRC="ARCHIve/ARCHIve/Camera/CameraController.swift"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

{
  echo "import Foundation"
  echo "import CoreGraphics"
  echo
  # Print the brace-balanced `enum CameraZoom { ... }` block verbatim.
  awk '
    /^enum CameraZoom \{/ {f=1}
    f {
      print
      for (i=1;i<=length($0);i++){c=substr($0,i,1); if(c=="{")d++; if(c=="}")d--}
      if (d==0) exit
    }' "$SRC"
} > "$WORK/main.swift"

cat >> "$WORK/main.swift" <<'SWIFT'

// switchovers are videoZoomFactor thresholds (ultra-wide = 1.0). The tele
// threshold is 2.0 × tele-optical-× on ultra-wide phones, tele-× on wide-first.
typealias L = CameraZoom.Lens
struct Case { let name: String; let sw: [CGFloat]; let lenses: [L]; let is48: Bool; let base: CGFloat; let want: [String] }
let cases: [Case] = [
  Case(name:"SE (single 12MP wide)",            sw:[],         lenses:[],           is48:false, base:1, want:["1"]),
  Case(name:"XR (single 12MP wide)",            sw:[],         lenses:[],           is48:false, base:1, want:["1"]),
  Case(name:"16e (single 48MP wide)",           sw:[],         lenses:[],           is48:true,  base:1, want:["1","2"]),
  Case(name:"iPhone Air (single 48MP wide)",    sw:[],         lenses:[],           is48:true,  base:1, want:["1","2"]),
  Case(name:"XS (dual: wide+tele 2x)",          sw:[2.0],      lenses:[.wide,.telephoto], is48:false, base:1, want:["1","2"]),
  Case(name:"11 (dual-wide 12MP)",              sw:[2.0],      lenses:[.ultraWide,.wide], is48:false, base:2, want:["0.5","1"]),
  Case(name:"13 / 14 (dual-wide 12MP)",         sw:[2.0],      lenses:[.ultraWide,.wide], is48:false, base:2, want:["0.5","1"]),
  Case(name:"15 / 16 (dual-wide 48MP)",         sw:[2.0],      lenses:[.ultraWide,.wide], is48:true,  base:2, want:["0.5","1","2"]),
  Case(name:"11 Pro / 12 Pro (triple tele 2x)", sw:[2.0,4.0],  lenses:[.ultraWide,.wide,.telephoto], is48:false, base:2, want:["0.5","1","2"]),
  Case(name:"12 Pro Max (triple tele 2.5x)",    sw:[2.0,5.0],  lenses:[.ultraWide,.wide,.telephoto], is48:false, base:2, want:["0.5","1","2.5"]),
  Case(name:"13 Pro / Max (triple tele 3x)",    sw:[2.0,6.0],  lenses:[.ultraWide,.wide,.telephoto], is48:false, base:2, want:["0.5","1","3"]),
  Case(name:"14 Pro / Max (triple tele 3x 48)", sw:[2.0,6.0],  lenses:[.ultraWide,.wide,.telephoto], is48:true,  base:2, want:["0.5","1","2","3"]),
  Case(name:"15 Pro (triple tele 3x 48)",       sw:[2.0,6.0],  lenses:[.ultraWide,.wide,.telephoto], is48:true,  base:2, want:["0.5","1","2","3"]),
  Case(name:"15 Pro Max (triple tele 5x 48)",   sw:[2.0,10.0], lenses:[.ultraWide,.wide,.telephoto], is48:true,  base:2, want:["0.5","1","2","5"]),
  Case(name:"16 Pro / Max (triple tele 5x 48)", sw:[2.0,10.0], lenses:[.ultraWide,.wide,.telephoto], is48:true,  base:2, want:["0.5","1","2","5"]),
]
var pass = 0, fail = 0
for c in cases {
  let (base, stops) = CameraZoom.model(switchovers: c.sw, lenses: c.lenses, is48MP: c.is48, maxAvailable: 100)
  let got = stops.map { $0.label }
  let ok = got == c.want && abs(base - c.base) < 0.001
  if ok { pass += 1 } else { fail += 1 }
  let name = c.name.padding(toLength: 34, withPad: " ", startingAt: 0)
  print("\(ok ? "PASS" : "FAIL")  \(name)  base=\(Int(base))x  got \(got)  want \(c.want)")
}
print("\n\(pass)/\(pass + fail) passed" + (fail == 0 ? "  all models correct" : "  \(fail) FAILED"))
if fail > 0 { exit 1 }
SWIFT

swiftc -O "$WORK/main.swift" -o "$WORK/zoomtest"
"$WORK/zoomtest"
