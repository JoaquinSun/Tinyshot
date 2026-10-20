import AppKit

/// Identifies the exact original offered at the start of a drag, so a replacement
/// or an edited file at the same path is never removed on completion.
struct FileFingerprint: Equatable {
    let inode: UInt64
    let device: UInt64
    let size: UInt64
    let modified: Date

    init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let device = attributes[.systemNumber] as? NSNumber,
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else {
            throw CocoaError(.fileReadUnknown)
        }
        self.inode = inode.uint64Value
        self.device = device.uint64Value
        self.size = size.uint64Value
        self.modified = modified
    }
}

struct DragTransfer {
    let id: UUID
    let shotID: UUID
    let originalURL: URL
    let fileURL: URL
    let fingerprint: FileFingerprint
    let shouldDeleteOriginal: Bool

    func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        // Some chat clients accept an image representation rather than a file
        // URL. Offer the full transfer image, never the downscaled preview.
        if let image = NSImage(contentsOf: fileURL), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        if fileURL.pathExtension.lowercased() == "png", let data = try? Data(contentsOf: fileURL) {
            item.setData(data, forType: .png)
        }
        return item
    }
}
