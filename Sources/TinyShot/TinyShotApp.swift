import AppKit
import SwiftUI
import Combine

@main
struct TinyShotApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum ShelfLayout {
    static func frame(for count: Int, preserving current: NSRect, within screen: NSRect) -> NSRect {
        let body: CGFloat = count == 0 ? 202 : min(CGFloat(count) * 224 + 24, 504)
        let height = min(body + ShelfMetrics.frameOverhead, screen.height)
        let width = min(ShelfMetrics.width, screen.width)
        // Keep the lower edge fixed when cards disappear. Preserving maxY here
        // would leave a one-card shelf floating where a two-card shelf began.
        let x = max(screen.minX, min(current.minX, screen.maxX - width))
        let y = max(screen.minY, min(current.minY, screen.maxY - height))
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ShotStore()
    private var monitor: ScreenshotMonitor!
    private var statusItem: NSStatusItem!
    private var shelf: FloatingPanel?
    private var dashboard: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid multiple processes competing for the same persistent shelf.
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1 {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "TinyShot 截图暂存")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "TinyShot · 点击显示截图，右键打开菜单"
        }
        monitor = ScreenshotMonitor(store: store)
        monitor.start()
        store.onNewShot = { [weak self] in self?.showShelf() }
        store.$shots.sink { [weak self] shots in
            guard let self else { return }
            self.statusItem.button?.title = shots.isEmpty ? "" : " \(shots.count)"
            self.resizeShelf(count: shots.count)
            if shots.isEmpty { self.shelf?.orderOut(nil) }
        }.store(in: &subscriptions)
        store.$liquidGlassEnabled.sink { [weak self] enabled in
            self?.applyWindowAppearance(glass: enabled)
        }.store(in: &subscriptions)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityAppearanceChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || store.monitorError != nil {
            showDashboard()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
        if !store.shots.isEmpty { showShelf() }
        if CommandLine.arguments.contains("--demo") { showDashboard(); store.addDemo() }
    }

    func applicationWillTerminate(_ notification: Notification) { monitor?.stop(); store.save() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return true
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "TinyShot · \(store.shots.count) 张待使用", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            let items: [(String, Selector, String)] = [
                ("显示截图暂存", #selector(showShelfAction), ""),
                ("打开 TinyShot…", #selector(showDashboardAction), ","),
                ("试试示例截图", #selector(addDemoAction), ""),
                ("退出 TinyShot", #selector(quit), "q")
            ]
            for (title, action, key) in items {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
                item.target = self
                menu.addItem(item)
            }
            if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button) }
        } else if shelf?.isVisible == true { shelf?.orderOut(nil) }
        else { showShelf() }
    }

    @objc private func showShelfAction() { showShelf() }
    @objc private func showDashboardAction() { showDashboard() }
    @objc private func addDemoAction() { store.addDemo() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screenChanged() { if shelf?.isVisible == true { positionShelf() } }
    @objc private func accessibilityAppearanceChanged() { applyWindowAppearance(glass: store.liquidGlassEnabled) }

    func showShelf() {
        if shelf == nil {
            let panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.title = "TinyShot 截图暂存"
            panel.contentView = ShelfHostingView(rootView: ShelfView(store: store,
                hide: { [weak self] in self?.shelf?.orderOut(nil) },
                openSettings: { [weak self] in self?.showDashboard(settings: true) }))
            shelf = panel
            applyWindowAppearance(glass: store.liquidGlassEnabled)
        }
        resizeShelf(count: store.shots.count)
        positionShelf()
        shelf?.orderFrontRegardless()
    }

    private func resizeShelf(count: Int) {
        guard let shelf else { return }
        guard let visibleFrame = (shelf.screen ?? NSScreen.main)?.visibleFrame else { return }
        shelf.setFrame(ShelfLayout.frame(for: count, preserving: shelf.frame, within: visibleFrame), display: true)
    }

    private func positionShelf() {
        guard let shelf else { return }
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        shelf.setFrameOrigin(NSPoint(x: frame.maxX - shelf.frame.width - 14, y: frame.minY + 18))
    }

    func showDashboard(settings: Bool = false) {
        if settings { store.selectedPage = 1 }
        if dashboard == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "TinyShot"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.hasShadow = true
            window.backgroundColor = NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.96, alpha: 1)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 900, height: 650)
            window.contentView = NSHostingView(rootView: DashboardView(store: store,
                showShelf: { [weak self] in self?.showShelf() },
                chooseFolder: { [weak self] in self?.chooseFolder() },
                openScreenshotOptions: { [weak self] in self?.openScreenshotOptions() }))
            window.center()
            dashboard = window
            applyWindowAppearance(glass: store.liquidGlassEnabled)
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
    }

    private func applyWindowAppearance(glass: Bool) {
        dashboard?.isOpaque = !glass
        dashboard?.backgroundColor = glass ? .clear : NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.96, alpha: 1)
        // Glass supplies its own outer edge and shadow. Avoid compositing a
        // second NSPanel shadow around the same translucent surface.
        let rendering = SurfaceRendering.resolve(enabled: glass,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            nativeAvailable: SurfaceRendering.nativeAvailable)
        shelf?.hasShadow = rendering != .liquidGlass
        DispatchQueue.main.async { [weak self] in
            self?.dashboard?.invalidateShadow()
            self?.shelf?.invalidateShadow()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择系统截图保存的文件夹"
        panel.message = "请与 ⇧⌘5 → 选项 → 存储到 的位置保持一致。此操作只设置 TinyShot。"
        panel.prompt = "监听此文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.folder
        guard let dashboard else { return }
        panel.beginSheetModal(for: dashboard) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.store.folder = url
            self.monitor.start()
        }
    }

    private func openScreenshotOptions() {
        let appURL = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.store.toast("请手动按 ⇧⌘5：\(error.localizedDescription)") } }
        }
    }
}
