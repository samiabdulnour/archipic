import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share-sheet entry point for Archipic. Accepts one or more images, lets the
/// user pick a Kind (Building / Element / Graphic), and drops each into the App
/// Group "Inbox" as a JPEG plus a tiny JSON sidecar. The app drains the inbox on
/// its next launch and creates the tagged Photo records (see ShareInbox in the
/// app target). This target never touches the SwiftData store directly.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let appGroup = "group.com.samiabdulnour.archive"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        loadImages { [weak self] images in
            guard let self else { return }
            if images.isEmpty { self.cancel() } else { self.present(images) }
        }
    }

    private func present(_ images: [UIImage]) {
        let root = ShareSaveView(
            images: images,
            onSave: { [weak self] type in self?.save(images, type: type) },
            onCancel: { [weak self] in self?.cancel() }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    // MARK: Load shared images

    private func loadImages(_ completion: @escaping ([UIImage]) -> Void) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap(\.attachments).flatMap { $0 }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) } ?? []
        guard !providers.isEmpty else { completion([]); return }

        var images = [UIImage?](repeating: nil, count: providers.count)
        let lock = NSLock()                 // completions arrive on arbitrary queues
        let group = DispatchGroup()
        for (i, provider) in providers.enumerated() {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data, let img = UIImage(data: data) {
                    lock.lock(); images[i] = img; lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(images.compactMap { $0 }) }
    }

    // MARK: Save to the App Group inbox / cancel

    private func save(_ images: [UIImage], type: String) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { cancel(); return }
        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let now = Date().timeIntervalSince1970
        var saved = 0
        for image in images {
            // One image at a time, drained each pass — several full-size encodes
            // alive at once is what gets a share extension jetsammed.
            autoreleasepool {
                guard let jpeg = Self.jpeg(image) else { return }
                let id = UUID().uuidString
                let jpg = inbox.appendingPathComponent("\(id).jpg")
                let json = inbox.appendingPathComponent("\(id).json")
                // The .json is the app's signal that the .jpg is complete, so write
                // the image atomically FIRST and only advertise it if that worked —
                // otherwise the app would find a sidecar with no image and bin both.
                guard (try? jpeg.write(to: jpg, options: .atomic)) != nil else { return }
                let meta: [String: Any] = ["type": type, "importedAt": now]
                guard let data = try? JSONSerialization.data(withJSONObject: meta),
                      (try? data.write(to: json, options: .atomic)) != nil else {
                    try? FileManager.default.removeItem(at: jpg)   // don't strand an orphan
                    return
                }
                saved += 1
            }
        }
        // Never report success for a photo we didn't actually store.
        guard saved > 0 else { cancel(); return }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "com.samiabdulnour.archive.share", code: 0))
    }

    /// Re-encode to JPEG, long side capped so a big web PNG doesn't bloat the store.
    private static func jpeg(_ image: UIImage, maxSide: CGFloat = 3024) -> Data? {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > maxSide else { return image.jpegData(compressionQuality: 0.9) }
        let scale = maxSide / longSide
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = image.scale   // don't 3× the pixels — the extension budget is ~120 MB
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.9)
    }
}

/// Minimal save sheet: a thumbnail, the three Kinds, and Save. Full tagging
/// happens later in the app. Kept self-contained — the extension can't reach the
/// app's Palette / TagVocab.
private struct ShareSaveView: View {
    let images: [UIImage]
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var type = "building"

    private let kinds: [(id: String, label: String, symbol: String)] = [
        ("building", "Building", "building.2"),
        ("element",  "Element",  "square.split.bottomrightquarter"),
        ("graphic",  "Graphic",  "doc.richtext"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let first = images.first {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: first).resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 200).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        if images.count > 1 {
                            Text("\(images.count) photos").font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule()).padding(8)
                        }
                    }
                }
                HStack(spacing: 10) {
                    ForEach(kinds, id: \.id) { k in
                        Button { type = k.id } label: {
                            VStack(spacing: 6) {
                                Image(systemName: k.symbol).font(.system(size: 20)).symbolVariant(.fill)
                                Text(k.label).font(.footnote.weight(.medium))
                            }
                            .frame(maxWidth: .infinity).frame(height: 66)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(type == k.id ? Color.accentColor.opacity(0.22) : Color(.secondarySystemBackground)))
                            .foregroundStyle(type == k.id ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Save to Archipic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(type) }.fontWeight(.semibold) }
            }
        }
    }
}
