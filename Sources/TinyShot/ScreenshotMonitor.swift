import Foundation
import Darwin

/// Watches the selected directory, never intercepts keys or changes macOS screenshot preferences.
final class ScreenshotMonitor {
    private let store: ShotStore
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var seen: Set<String> = []
    private var pending: [String: Int] = [:]
    private var scanWork: DispatchWorkItem?
    private var folder: URL?

    init(store: ShotStore) { self.store = store }

    func start() {
        stop()
        folder = store.folder
        do {
            seen = Set(try contents().map(\.path))
            store.monitorError = nil
        } catch {
            store.monitorError = "无法读取截图文件夹。请在偏好设置中重新选择，并允许访问。"
            store.monitoring = false
            return
        }
        let fd = open(store.folder.path, O_EVTONLY)
        guard fd >= 0 else {
            store.monitorError = "无法监听此文件夹，请重新选择截图保存位置。"
            return
        }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .revoke], queue: .main)
        watcher.setEventHandler { [weak self] in
            guard let self else { return }
            if !watcher.data.intersection([.delete, .rename, .revoke]).isEmpty {
                self.store.monitorError = "截图文件夹已移动或不可访问，请重新选择。"
                self.stop()
                return
            }
            self.scanWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.scan() }
            self.scanWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
        watcher.setCancelHandler { close(fd) }
        source = watcher
        watcher.resume()
        store.monitoring = true
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.scan()
            self?.store.expire()
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        timer?.invalidate()
        timer = nil
        scanWork?.cancel()
        pending = [:]
        store.monitoring = false
    }

    private func contents() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder ?? store.folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
    }

    private func scan() {
        do {
            let urls = try contents()
            let current = Set(urls.map(\.path))
            seen.formIntersection(current)
            pending = pending.filter { current.contains($0.key) }
            let prefix = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture")?["name"] as? String
            for url in urls where !seen.contains(url.path) {
                guard ShotRecognition.extensions.contains(url.pathExtension.lowercased()),
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    seen.insert(url.path)
                    continue
                }
                if ShotRecognition.isScreenshot(url, customPrefix: prefix), store.add(url) {
                    seen.insert(url.path)
                    pending.removeValue(forKey: url.path)
                } else {
                    // Metadata and file contents can arrive after the directory event.
                    let attempts = (pending[url.path] ?? 0) + 1
                    if attempts >= 15 { seen.insert(url.path); pending.removeValue(forKey: url.path) }
                    else { pending[url.path] = attempts }
                }
            }
            store.monitorError = nil
        } catch {
            store.monitorError = "无法读取截图文件夹，请检查访问权限或重新选择。"
            stop()
        }
    }
}
