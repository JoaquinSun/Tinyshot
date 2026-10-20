import AppKit
import Combine
import CoreServices
import ImageIO

struct Shot: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var path: String
    var createdAt: Date = Date()
    var isDemo = false
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

enum Retention: Int, CaseIterable, Identifiable {
    case untilUsed = 0, oneMinute = 60, fiveMinutes = 300, fifteenMinutes = 900
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .untilUsed: return "一直保留，直到用完"
        case .oneMinute: return "1 分钟后收起"
        case .fiveMinutes: return "5 分钟后收起"
        case .fifteenMinutes: return "15 分钟后收起"
        }
    }
    func isExpired(_ shot: Shot, now: Date) -> Bool {
        rawValue > 0 && now.timeIntervalSince(shot.createdAt) >= Double(rawValue)
    }
}

enum ShotRecognition {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "pdf"]
    static func matchesName(_ url: URL, customPrefix: String?) -> Bool {
        guard extensions.contains(url.pathExtension.lowercased()) else { return false }
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        var prefixes = ["screenshot", "screen shot", "截屏", "屏幕快照", "螢幕截圖", "スクリーンショット", "스크린샷", "bildschirmfoto", "capture d’écran", "capture d'écran", "captura de pantalla"]
        if let prefix = customPrefix, !prefix.isEmpty { prefixes.append(prefix.lowercased()) }
        return prefixes.contains { name.hasPrefix($0) }
    }
    static func isScreenshot(_ url: URL, customPrefix: String?) -> Bool {
        guard extensions.contains(url.pathExtension.lowercased()) else { return false }
        if let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
           let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool, flag {
            return true
        }
        return matchesName(url, customPrefix: customPrefix)
    }
}

final class ShotStore: ObservableObject {
    @Published private(set) var shots: [Shot] = []
    @Published private(set) var recent: [Shot] = []
    @Published var notice: String?
    @Published var monitorError: String?
    @Published var monitoring = false
    @Published var selectedPage = 0
    @Published var liquidGlassEnabled: Bool { didSet { defaults.set(liquidGlassEnabled, forKey: "liquidGlassEnabled") } }
    @Published var autoDismiss: Bool { didSet { defaults.set(autoDismiss, forKey: "autoDismiss") } }
    @Published var deleteAfterDrag: Bool { didSet { defaults.set(deleteAfterDrag, forKey: "deleteAfterDrag") } }
    @Published var retention: Retention { didSet { defaults.set(retention.rawValue, forKey: "retention") } }
    @Published var folder: URL { didSet { defaults.set(folder.path, forKey: "folder") } }
    var onNewShot: (() -> Void)?
    private let defaults: UserDefaults
    private let storageURL: URL
    private let removeOriginal: (URL) throws -> Void
    private var activeTransfers: [UUID: DragTransfer] = [:]
    private var lastTransferCleanup = Date.distantPast
    private var transfersURL: URL { storageURL.deletingLastPathComponent().appendingPathComponent("Transfers", isDirectory: true) }
    private var thumbnails: [UUID: NSImage] = [:]
    private var noticeID = UUID()

    init(defaults: UserDefaults = .standard, storageURL: URL? = nil,
         removeOriginal: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.defaults = defaults
        liquidGlassEnabled = defaults.object(forKey: "liquidGlassEnabled") as? Bool ?? true
        self.removeOriginal = removeOriginal
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TinyShot", isDirectory: true)
        self.storageURL = (storageURL ?? support.appendingPathComponent("shelf.json")).standardizedFileURL.resolvingSymlinksInPath()
        autoDismiss = defaults.object(forKey: "autoDismiss") as? Bool ?? true
        deleteAfterDrag = defaults.object(forKey: "deleteAfterDrag") as? Bool ?? true
        retention = Retention(rawValue: defaults.integer(forKey: "retention")) ?? .untilUsed
        let systemLocation = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture")?["location"] as? String
        let path = defaults.string(forKey: "folder") ?? systemLocation ?? "~/Desktop"
        folder = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        if let data = try? Data(contentsOf: self.storageURL), let state = try? JSONDecoder().decode(SavedState.self, from: data) {
            shots = state.shots.filter { FileManager.default.fileExists(atPath: $0.path) }
            recent = state.recent.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        expire()
        cleanupTransfers()
    }

    private struct SavedState: Codable { var shots: [Shot]; var recent: [Shot] }

    func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(SavedState(shots: shots, recent: recent)).write(to: storageURL, options: .atomic)
        } catch { toast("暂存记录保存失败：\(error.localizedDescription)") }
    }

    @discardableResult func add(_ inputURL: URL, demo: Bool = false) -> Bool {
        let url = inputURL.standardizedFileURL.resolvingSymlinksInPath()
        guard !shots.contains(where: { $0.path == url.path }),
              let image = NSImage(contentsOf: url), image.isValid else { return false }
        let shot = Shot(path: url.path, isDemo: demo)
        shots.insert(shot, at: 0)
        recent.removeAll { $0.path == url.path }
        save()
        onNewShot?()
        return true
    }

    func finish(_ shot: Shot) {
        guard autoDismiss else { toast("已使用 · 截图继续保留"); return }
        dismiss(shot)
    }

    /// The destination receives a stable app-owned copy, never the file that may
    /// be deleted after acceptance. Cancellation cannot trigger original deletion.
    func prepareDrag(_ shot: Shot) throws -> DragTransfer {
        cleanupTransfers()
        let fingerprint = try FileFingerprint(url: shot.url)
        let id = UUID()
        let directory = transfersURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent(shot.url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: shot.url, to: fileURL)
            guard try FileFingerprint(url: shot.url) == fingerprint else { throw CocoaError(.fileReadUnknown) }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        let transfer = DragTransfer(id: id, shotID: shot.id, originalURL: shot.url, fileURL: fileURL,
            fingerprint: fingerprint, shouldDeleteOriginal: deleteAfterDrag && !isTransferFile(shot.url))
        activeTransfers[id] = transfer
        return transfer
    }

    func completeDrag(_ transfer: DragTransfer, accepted: Bool) {
        // Consume our own session record exactly once. Never trust a callback to
        // supply an arbitrary original path to delete.
        guard let active = activeTransfers.removeValue(forKey: transfer.id) else { return }
        guard accepted else {
            try? FileManager.default.removeItem(at: active.fileURL.deletingLastPathComponent())
            return
        }
        guard active.shouldDeleteOriginal && deleteAfterDrag else {
            if let shot = shots.first(where: { $0.id == active.shotID }) { finish(shot) }
            return
        }
        do {
            guard try FileFingerprint(url: active.originalURL) == active.fingerprint else {
                toast("已拖出，但原图已被修改，未删除；请手动检查")
                return
            }
            try removeOriginal(active.originalURL)
        } catch {
            toast("已拖出，但原图删除失败；请检查文件或访问权限")
            return
        }
        // A retained card reads the transfer copy. Deleted originals are not
        // advertised as recoverable in Recent, even when dismissed mid-drag.
        recent.removeAll { $0.id == active.shotID || $0.path == active.originalURL.path }
        if let index = shots.firstIndex(where: { $0.id == active.shotID }) {
            shots[index].path = active.fileURL.path
            let updated = shots[index]
            save()
            finish(updated)
        } else { save() }
        toast("已拖出，原截图已直接删除")
    }

    func isTransferFile(_ url: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(
            transfersURL.standardizedFileURL.resolvingSymlinksInPath().path + "/")
    }

    /// Never expire files backing a retained card or an active drag. Accepted
    /// uploads keep a 24-hour reading window, including across app restarts.
    func cleanupTransfers(now: Date = Date()) {
        guard now.timeIntervalSince(lastTransferCleanup) >= 3600 else { return }
        lastTransferCleanup = now
        let protected = (shots.map(\.path) + recent.map(\.path) + activeTransfers.values.map { $0.fileURL.path })
            .map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path }
        guard let directories = try? FileManager.default.contentsOfDirectory(at: transfersURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]) else { return }
        for directory in directories {
            guard UUID(uuidString: directory.lastPathComponent) != nil,
                  let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let created = values.creationDate, now.timeIntervalSince(created) >= 86400,
                  !protected.contains(where: { $0.hasPrefix(directory.standardizedFileURL.resolvingSymlinksInPath().path + "/") }) else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func dismiss(_ shot: Shot) {
        guard shots.contains(where: { $0.id == shot.id }) else { return }
        shots.removeAll { $0.id == shot.id }
        thumbnails.removeValue(forKey: shot.id)
        recent.removeAll { $0.path == shot.path }
        if !isTransferFile(shot.url) { recent.insert(shot, at: 0) }
        recent = Array(recent.prefix(24))
        save()
    }

    /// An explicit × means deleting this screenshot, unlike automatic dismissal.
    /// Resolve the current record by ID so a stale view cannot delete an old path.
    func deleteShot(_ shot: Shot) {
        guard let current = shots.first(where: { $0.id == shot.id }) else { return }
        if !isTransferFile(current.url) {
            do {
                // Refuse directories or symlinks that replaced the screenshot.
                _ = try FileFingerprint(url: current.url)
                try removeOriginal(current.url)
            } catch {
                let cocoa = error as NSError
                let alreadyMissing = cocoa.domain == NSCocoaErrorDomain &&
                    [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(cocoa.code)
                guard alreadyMissing else {
                    toast("截图删除失败，卡片已保留；请检查文件或访问权限")
                    return
                }
            }
        }
        // A transfer-backed card has already had its original deleted. Its
        // upload copy keeps the existing grace period so a reader isn't broken.
        shots.removeAll { $0.id == current.id }
        thumbnails.removeValue(forKey: current.id)
        recent.removeAll { $0.id == current.id || $0.path == current.path }
        save()
        toast("截图已删除")
    }

    func restore(_ shot: Shot) {
        guard FileManager.default.fileExists(atPath: shot.path) else { toast("原始文件已移动或删除"); return }
        guard !shots.contains(where: { $0.path == shot.path }) else { return }
        recent.removeAll { $0.id == shot.id }
        var restored = shot
        restored.createdAt = Date()
        shots.insert(restored, at: 0)
        save()
        onNewShot?()
    }

    func copy(_ shot: Shot) {
        guard let image = NSImage(contentsOf: shot.url) else { toast("无法读取图片，原始文件可能已移动"); return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([image]) else { toast("复制失败，请重试"); return }
        toast("已复制，可以粘贴给 AI")
        finish(shot)
    }

    func expire(now: Date = Date()) {
        for shot in shots where retention.isExpired(shot, now: now) { dismiss(shot) }
        cleanupTransfers(now: now)
    }

    func image(for shot: Shot) -> NSImage? {
        if let cached = thumbnails[shot.id] { return cached }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 800, kCGImageSourceCreateThumbnailWithTransform: true]
        let image: NSImage?
        if let source = CGImageSourceCreateWithURL(shot.url as CFURL, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            image = NSImage(cgImage: cg, size: .zero)
        } else { image = NSImage(contentsOf: shot.url) }
        if let image { thumbnails[shot.id] = image }
        return image
    }

    func toast(_ message: String) {
        let token = UUID()
        noticeID = token
        notice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.noticeID == token { self?.notice = nil }
        }
    }

    func addDemo() {
        let url = storageURL.deletingLastPathComponent().appendingPathComponent("TinyShot 示例-\(UUID().uuidString.prefix(6)).png")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try DemoImage.png().write(to: url)
            _ = add(url, demo: true)
        } catch { toast("无法创建示例：\(error.localizedDescription)") }
    }
}

enum DemoImage {
    static func png() -> Data {
        let image = NSImage(size: NSSize(width: 960, height: 540))
        image.lockFocus()
        NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 960, height: 540)).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 105, y: 65, width: 750, height: 410), xRadius: 20, yRadius: 20).fill()
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.27, blue: 0.23, alpha: 1)]
        ("一个灵感，随手截下。" as NSString).draw(at: NSPoint(x: 150, y: 374), withAttributes: title)
        ("TinyShot / 截图示例" as NSString).draw(at: NSPoint(x: 152, y: 433), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.gray])
        for (index, width) in [590.0, 510.0, 560.0].enumerated() {
            NSColor(calibratedWhite: 0.9, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 152, y: 320 - Double(index) * 32, width: width, height: 10), xRadius: 5, yRadius: 5).fill()
        }
        let heights = [42.0, 70.0, 55.0, 98.0, 83.0, 126.0, 114.0, 150.0]
        for (index, height) in heights.enumerated() {
            NSColor(calibratedRed: 0.30, green: 0.58 + Double(index) * 0.025, blue: 0.46, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 160 + Double(index) * 76, y: 96, width: 44, height: height), xRadius: 7, yRadius: 7).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }
}
