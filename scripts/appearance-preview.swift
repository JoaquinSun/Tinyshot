// Isolated visual QA harness: uses generated images and temporary state only.
// Compile with the UI/model sources, excluding TinyShotApp.swift.
import AppKit
import SwiftUI
import Combine

@main
struct AppearancePreview {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = PreviewDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var panel: NSPanel!
    private var store: ShotStore!
    private var theme: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TinyShot-Appearance-QA")
        let preferences = UserDefaults.standard
        preferences.removePersistentDomain(forName: "com.tinyshot.appearance-qa")
        store = ShotStore(defaults: preferences, storageURL: directory.appendingPathComponent("state.json"))
        store.selectedPage = 1
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 790),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "TinyShot 外观预览"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DashboardView(store: store, showShelf: { [weak self] in self?.showShelf() },
            chooseFolder: {}, openScreenshotOptions: {}))
        window.center()
        theme = store.$liquidGlassEnabled.sink { [weak self] enabled in
            self?.window.isOpaque = !enabled
            self?.window.backgroundColor = enabled ? .clear : .windowBackgroundColor
        }
        if store.shots.isEmpty { store.addDemo() }
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quit = NSMenuItem(title: "退出外观预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if Bundle.main.object(forInfoDictionaryKey: "PreviewShelf") as? Bool == true {
            for shot in store.shots { store.dismiss(shot) }
            showShelf()
            // A colored backdrop makes white rectangular padding and opaque
            // corners visible during QA; a white desktop hides those defects.
            window.contentView = NSHostingView(rootView:
                LinearGradient(colors: [.indigo, .teal, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea())
            window.isOpaque = true
            window.backgroundColor = .systemIndigo
            window.setFrame(panel.frame.insetBy(dx: -30, dy: -30), display: true)
            window.orderFront(nil)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func showShelf() {
        if panel == nil {
            let frame = NSScreen.main!.visibleFrame
            panel = PreviewShelfPanel(contentRect: NSRect(x: frame.maxX - ShelfMetrics.width - 14, y: frame.minY + 18,
                                                        width: ShelfMetrics.width, height: 202 + ShelfMetrics.frameOverhead),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "TinyShot 托盘外观预览"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = SurfaceRendering.resolve(enabled: store.liquidGlassEnabled,
                reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                nativeAvailable: SurfaceRendering.nativeAvailable) != .liquidGlass
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = ShelfHostingView(rootView: ShelfView(store: store,
                hide: { [weak self] in self?.panel.orderOut(nil) },
                openSettings: { [weak self] in self?.window.makeKeyAndOrderFront(nil) }))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Bundle.main.object(forInfoDictionaryKey: "PreviewShelf") as? Bool != true
    }
}

final class PreviewShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
