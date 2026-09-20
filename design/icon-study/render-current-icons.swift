import UIKit
// Render the app's CURRENT tag icons exactly as TagForm.symbolArt draws them:
// SF Symbol, 21 pt regular, fill variant where one exists. Black on clear, so
// the page can tint them like a template image.
let names: [(String, String)] = [
  ("wall","rectangle.portrait"), ("column","building.columns"), ("beam","rectangle"), ("slab","square"),
  ("stair","stairs"), ("door","door.left.hand.closed"), ("window","rectangle.split.2x2"), ("roof","triangle"),
  ("m-concrete","square.grid.3x3.fill"), ("m-brick","rectangle.split.3x1.fill"), ("m-stone","mountain.2.fill"),
  ("m-timber","tree.fill"), ("m-metal","circle.hexagongrid.fill"), ("m-glass","cube.transparent"),
  ("m-plaster","paintbrush.fill"), ("m-tile","checkerboard.rectangle"), ("m-fabric","curtains.closed"), ("m-other","ellipsis"),
  ("r-outdoor","building.2"), ("r-lobby","door.left.hand.open"), ("r-hall","rectangle.portrait"), ("r-living","sofa"),
  ("r-bedroom","bed.double"), ("r-workspace","laptopcomputer"), ("r-kitchen","fork.knife"), ("r-bathroom","shower"),
  ("r-dining","fork.knife"), ("r-meeting","person.3"), ("r-auditorium","theatermasks"), ("r-library","books.vertical"),
  ("r-shop","cart"), ("r-showroom","bag"), ("r-bar","wineglass"), ("r-spa","drop"), ("r-lab","testtube.2"),
  ("r-mechanical","gearshape.2"), ("r-chapel","cross"), ("r-storage","archivebox"), ("r-service","wrench.and.screwdriver"),
  ("r-stairs","stairs"), ("r-atrium","building.columns"), ("r-lounge","sofa"), ("r-window","rectangle.split.2x2"),
  ("r-counter","rectangle.split.3x1"), ("r-other","ellipsis"),
]
let outDir = CommandLine.arguments[1]
let cfg = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
for (key, name) in names {
    let filled = name.hasSuffix(".fill") ? nil : UIImage(systemName: name + ".fill", withConfiguration: cfg)
    guard let img = filled ?? UIImage(systemName: name, withConfiguration: cfg) else { print("MISSING \(name)"); continue }
    let side: CGFloat = 34; let wide: CGFloat = 48
    let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 8; fmt.opaque = false
    let out = UIGraphicsImageRenderer(size: CGSize(width: wide, height: side), format: fmt).image { _ in
        let t = img.withTintColor(.black, renderingMode: .alwaysOriginal)
        t.draw(in: CGRect(x: (wide - t.size.width) / 2, y: (side - t.size.height) / 2,
                          width: t.size.width, height: t.size.height))
    }
    try? out.pngData()?.write(to: URL(fileURLWithPath: "\(outDir)/sf-\(key).png"))
    print("\(key): \(name)\(filled != nil ? ".fill" : "")  \(Int(img.size.width))x\(Int(img.size.height)) pt")
}
