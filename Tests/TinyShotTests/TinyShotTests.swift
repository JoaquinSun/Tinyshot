import Testing
import Foundation
import AppKit
@testable import TinyShot

@Suite(.serialized)
@MainActor
final class TinyShotTests {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("TinyShotTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "TinyShotTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(directory.path, forKey: "folder")
    }
    deinit {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
    private func makeStore() -> ShotStore { ShotStore(defaults: defaults, storageURL: directory.appendingPathComponent("state.json")) }
    private func imageURL() throws -> URL {
        let url = directory.appendingPathComponent("Screenshot-test.png")
        // A real, decodable 1×1 PNG, independent of AppKit drawing or a window server.
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGP4/x8AAwAB//wl3FEAAAAASUVORK5CYII=")!
        try data.write(to: url)
        return url
    }
    @Test func testScreenshotNamesAndCustomPrefixes() {
        #expect(ShotRecognition.matchesName(URL(fileURLWithPath: "/tmp/截屏2026-10-20.png"), customPrefix: nil))
        #expect(ShotRecognition.matchesName(URL(fileURLWithPath: "/tmp/Work capture 2026.png"), customPrefix: "Work capture"))
        #expect(!(ShotRecognition.matchesName(URL(fileURLWithPath: "/tmp/holiday.png"), customPrefix: nil)))
        #expect(!(ShotRecognition.matchesName(URL(fileURLWithPath: "/tmp/Screenshot.txt"), customPrefix: nil)))
        #expect(!(ShotRecognition.matchesName(URL(fileURLWithPath: "/tmp/holiday.png"), customPrefix: "")))
    }

    @Test func testGlassPreferencePersistsAcrossRestartWithoutChangingOtherSettings() {
        let store = makeStore()
        #expect(store.liquidGlassEnabled)
        store.liquidGlassEnabled = false
        #expect(!makeStore().liquidGlassEnabled)
        #expect(store.autoDismiss)
        #expect(store.deleteAfterDrag)
        store.liquidGlassEnabled = true
        #expect(makeStore().liquidGlassEnabled)
    }

    @Test func testGlassUsesNativeFallbackAndAccessibilityPreferences() {
        #expect(SurfaceRendering.resolve(enabled: true, reduceTransparency: false, nativeAvailable: true) == .liquidGlass)
        #expect(SurfaceRendering.resolve(enabled: true, reduceTransparency: false, nativeAvailable: false) == .frosted)
        #expect(SurfaceRendering.resolve(enabled: true, reduceTransparency: true, nativeAvailable: true) == .solid)
        #expect(SurfaceRendering.resolve(enabled: false, reduceTransparency: false, nativeAvailable: true) == .solid)
    }
    @Test func testCancelledOrUnusedShotPersistsAcrossRestart() throws {
        let store = makeStore()
        #expect(store.add(try imageURL()))
        #expect(makeStore().shots.count == 1)
        #expect(makeStore().recent.count == 0)
    }
    @Test func testUsedShotMovesToRecentWithoutDeletingOriginalAndCanRestore() throws {
        let store = makeStore()
        let url = try imageURL()
        #expect(store.add(url))
        store.finish(store.shots[0])
        #expect(store.shots.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(makeStore().recent.count == 1)
        store.restore(store.recent[0])
        #expect(store.shots.count == 1)
        #expect(store.recent.isEmpty)
    }
    @Test func testAutoDismissCanBeDisabledAndDuplicateFilesAreIgnored() throws {
        let store = makeStore()
        let url = try imageURL()
        store.autoDismiss = false
        #expect(store.add(url))
        #expect(!(store.add(url)))
        store.finish(store.shots[0])
        #expect(store.shots.count == 1)
        #expect(!(makeStore().autoDismiss))
    }
    @Test func testRetentionBoundaryAndForever() {
        let shot = Shot(path: "/tmp/a.png", createdAt: Date(timeIntervalSince1970: 100))
        #expect(!(Retention.oneMinute.isExpired(shot, now: Date(timeIntervalSince1970: 159))))
        #expect(Retention.oneMinute.isExpired(shot, now: Date(timeIntervalSince1970: 160)))
        #expect(!(Retention.untilUsed.isExpired(shot, now: Date(timeIntervalSince1970: 1_000_000))))
    }
    @Test func testDeletedOriginalIsNotRestoredOnRestart() throws {
        let store = makeStore()
        let url = try imageURL()
        #expect(store.add(url))
        try FileManager.default.removeItem(at: url)
        #expect(makeStore().shots.isEmpty)
    }

    @Test func testAcceptedDragDeletesOriginalAndKeepsReadableTransfer() throws {
        let store = makeStore()
        let url = try imageURL()
        let bytes = try Data(contentsOf: url)
        #expect(store.add(url))
        let transfer = try store.prepareDrag(store.shots[0])
        #expect(transfer.originalURL != transfer.fileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        store.completeDrag(transfer, accepted: true)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: transfer.fileURL) == bytes)
        #expect(store.shots.isEmpty)
        #expect(store.recent.isEmpty)
        #expect(makeStore().recent.isEmpty)
        // Duplicate native completion notifications must be harmless.
        store.completeDrag(transfer, accepted: true)
        #expect(try Data(contentsOf: transfer.fileURL) == bytes)
    }

    @Test func testCancelledDragDoesNotDeleteOrDismiss() throws {
        let store = makeStore()
        let url = try imageURL()
        #expect(store.add(url))
        let transfer = try store.prepareDrag(store.shots[0])
        store.completeDrag(transfer, accepted: false)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: transfer.fileURL.path))
        #expect(store.shots.count == 1)
        #expect(store.recent.isEmpty)
        store.completeDrag(transfer, accepted: true)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func testDeleteOptionCanBeDisabledAndPersists() throws {
        let store = makeStore()
        store.deleteAfterDrag = false
        let url = try imageURL()
        #expect(store.add(url))
        let transfer = try store.prepareDrag(store.shots[0])
        store.completeDrag(transfer, accepted: true)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(store.shots.isEmpty)
        #expect(store.recent.count == 1)
        #expect(!makeStore().deleteAfterDrag)
    }

    @Test func testOptionDisabledDuringDragPreventsDeletion() throws {
        let store = makeStore()
        let url = try imageURL()
        #expect(store.add(url))
        let transfer = try store.prepareDrag(store.shots[0])
        store.deleteAfterDrag = false
        store.completeDrag(transfer, accepted: true)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func testChangedOriginalIsPreservedAfterAcceptedDrag() throws {
        let store = makeStore()
        let url = try imageURL()
        #expect(store.add(url))
        let transfer = try store.prepareDrag(store.shots[0])
        let newBytes = Data("a different file now occupies this path".utf8)
        try newBytes.write(to: url, options: .atomic)
        store.completeDrag(transfer, accepted: true)
        #expect(try Data(contentsOf: url) == newBytes)
        #expect(store.shots.count == 1)
        #expect(store.notice?.contains("未删除") == true)
    }

    @Test func testDeletionFailurePreservesCardAndReadableTransfer() throws {
        let store = ShotStore(defaults: defaults, storageURL: directory.appendingPathComponent("state.json"),
            removeOriginal: { _ in throw CocoaError(.fileWriteNoPermission) })
        let url = try imageURL()
        #expect(store.add(url))
        let transfer = try store.prepareDrag(store.shots[0])
        store.completeDrag(transfer, accepted: true)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: transfer.fileURL.path))
        #expect(store.shots.count == 1)
        #expect(store.notice?.contains("删除失败") == true)
    }

    @Test func testRetainedCardUsesTransferAndDoesNotDeleteItOnSubsequentDrag() throws {
        let store = makeStore()
        store.autoDismiss = false
        let url = try imageURL()
        #expect(store.add(url))
        let transfer = try store.prepareDrag(store.shots[0])
        store.completeDrag(transfer, accepted: true)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.shots.count == 1)
        #expect(store.shots.first?.path == transfer.fileURL.path)
        let repeated = try store.prepareDrag(store.shots[0])
        store.completeDrag(repeated, accepted: true)
        #expect(FileManager.default.fileExists(atPath: transfer.fileURL.path))
        #expect(makeStore().shots.count == 1)
        // Even an old transfer cannot expire while a card still needs it.
        store.cleanupTransfers(now: Date().addingTimeInterval(90_000))
        #expect(FileManager.default.fileExists(atPath: transfer.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: repeated.fileURL.path))
        store.dismiss(store.shots[0])
        #expect(store.recent.isEmpty)
        store.cleanupTransfers(now: Date().addingTimeInterval(100_000))
        #expect(!FileManager.default.fileExists(atPath: transfer.fileURL.path))
    }

    @Test func testTemporaryTransferRemainsFor24HoursThenExpires() throws {
        let store = makeStore()
        let url = try imageURL()
        #expect(store.add(url))
        let transfer = try store.prepareDrag(store.shots[0])
        store.completeDrag(transfer, accepted: true)
        store.cleanupTransfers(now: Date().addingTimeInterval(3600))
        #expect(FileManager.default.fileExists(atPath: transfer.fileURL.path))
        store.cleanupTransfers(now: Date().addingTimeInterval(90_000))
        #expect(!FileManager.default.fileExists(atPath: transfer.fileURL.path))
    }

    @Test func testCrossDeletesOnlyItsScreenshotAndDoesNotOfferRestore() throws {
        let store = makeStore()
        store.deleteAfterDrag = false // Manual deletion is independent of drag settings.
        let first = try imageURL()
        let second = directory.appendingPathComponent("Screenshot-other.png")
        try FileManager.default.copyItem(at: first, to: second)
        #expect(store.add(first))
        let firstShot = try #require(store.shots.first)
        #expect(store.add(second))
        store.deleteShot(firstShot)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(store.shots.count == 1)
        #expect(store.recent.isEmpty)
        #expect(makeStore().shots.count == 1)
        #expect(makeStore().recent.isEmpty)
    }

    @Test func testCrossDeletionFailureKeepsFileAndCard() throws {
        let store = ShotStore(defaults: defaults, storageURL: directory.appendingPathComponent("state.json"),
            removeOriginal: { _ in throw CocoaError(.fileWriteNoPermission) })
        let url = try imageURL()
        #expect(store.add(url))
        store.deleteShot(store.shots[0])
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(store.shots.count == 1)
        #expect(store.recent.isEmpty)
        #expect(store.notice?.contains("删除失败") == true)
    }

    @Test func testCrossRemovesCardWhenOriginalIsAlreadyMissing() throws {
        let store = makeStore()
        let url = try imageURL()
        #expect(store.add(url))
        try FileManager.default.removeItem(at: url)
        store.deleteShot(store.shots[0])
        #expect(store.shots.isEmpty)
        #expect(store.recent.isEmpty)
        #expect(makeStore().shots.isEmpty)
    }

    @Test func testStaleCrossCannotDeleteNewFileAtOldPath() throws {
        let store = makeStore()
        let url = try imageURL()
        #expect(store.add(url))
        let staleShot = store.shots[0]
        store.deleteShot(staleShot)
        let replacement = Data("unrelated replacement file".utf8)
        try replacement.write(to: url)
        store.deleteShot(staleShot)
        #expect(try Data(contentsOf: url) == replacement)
    }

    @Test func testCrossDoesNotRecursivelyDeleteDirectoryReplacingScreenshot() throws {
        let store = makeStore()
        let url = try imageURL()
        #expect(store.add(url))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let marker = url.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: marker)
        store.deleteShot(store.shots[0])
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(store.shots.count == 1)
        #expect(store.notice?.contains("删除失败") == true)
    }

    @Test func testCrossAfterDragKeepsUploadCopyButRemovesCard() throws {
        let store = makeStore()
        store.autoDismiss = false
        let url = try imageURL()
        #expect(store.add(url))
        let staleShot = store.shots[0]
        let transfer = try store.prepareDrag(staleShot)
        store.completeDrag(transfer, accepted: true)
        store.deleteShot(staleShot)
        #expect(store.shots.isEmpty)
        #expect(store.recent.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: transfer.fileURL.path))
        store.cleanupTransfers(now: Date().addingTimeInterval(90_000))
        #expect(!FileManager.default.fileExists(atPath: transfer.fileURL.path))
    }

    @Test func testImageGestureCannotBeUsedAsAWindowMove() {
        let view = ShotDragView()
        #expect(!view.mouseDownCanMoveWindow)
    }

    @Test func testDragOffersRealFileAndFullImageToChatClients() throws {
        let store = makeStore()
        let url = try imageURL()
        let bytes = try Data(contentsOf: url)
        #expect(store.add(url))
        let transfer = try store.prepareDrag(store.shots[0])
        let item = transfer.pasteboardItem()
        #expect(item.string(forType: .fileURL) == transfer.fileURL.absoluteString)
        #expect(item.data(forType: .png) == bytes)
        let tiff = try #require(item.data(forType: .tiff))
        let image = try #require(NSBitmapImageRep(data: tiff))
        #expect(image.pixelsWide == 1)
        #expect(image.pixelsHigh == 1)
        store.completeDrag(transfer, accepted: false)
    }

    @Test func testRemovingLowerCardKeepsShelfAtBottomOfScreen() {
        let screen = NSRect(x: 0, y: 60, width: 1440, height: 816)
        let docked = NSRect(x: 1090, y: 78, width: 336, height: 337)
        let twoCards = ShelfLayout.frame(for: 2, preserving: docked, within: screen)
        let oneCard = ShelfLayout.frame(for: 1, preserving: twoCards, within: screen)
        #expect(twoCards.minY == docked.minY)
        #expect(oneCard.minY == docked.minY)
        #expect(oneCard.minX == docked.minX)
        #expect(oneCard.maxY < twoCards.maxY)
        #expect(oneCard.height == docked.height)
    }

    @Test func testShelfResizeStaysOnItsDisplayWhenScreenOriginIsNegative() {
        let screen = NSRect(x: -1920, y: -200, width: 1920, height: 1000)
        let current = NSRect(x: -350, y: -182, width: 336, height: 337)
        let expanded = ShelfLayout.frame(for: 5, preserving: current, within: screen)
        let shrunk = ShelfLayout.frame(for: 1, preserving: expanded, within: screen)
        #expect(shrunk.minY == current.minY)
        #expect(shrunk.minX == current.minX)
        #expect(screen.contains(expanded))
    }

    @Test func testMonitorOnlyAddsNewScreenshotsAndRetriesIncompleteFile() throws {
        _ = try imageURL() // Existing files must not flood the shelf on startup.
        let store = makeStore()
        let monitor = ScreenshotMonitor(store: store)
        monitor.start()
        defer { monitor.stop() }
        #expect(store.monitoring)
        #expect(store.shots.isEmpty)
        let incoming = directory.appendingPathComponent("Screenshot-new.png")
        try Data().write(to: incoming)
        spin(for: 0.4)
        #expect(store.shots.isEmpty)
        try Data(contentsOf: directory.appendingPathComponent("Screenshot-test.png")).write(to: incoming)
        let deadline = Date().addingTimeInterval(4)
        while store.shots.isEmpty && Date() < deadline { spin(for: 0.05) }
        #expect(store.shots.count == 1)
        #expect(store.shots.first?.path == incoming.resolvingSymlinksInPath().path)
        let other = directory.appendingPathComponent("ordinary-photo.png")
        try Data(contentsOf: incoming).write(to: other)
        spin(for: 0.5)
        #expect(store.shots.count == 1)
    }

    private func spin(for duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline { _ = RunLoop.main.run(mode: .default, before: deadline) }
    }
}
