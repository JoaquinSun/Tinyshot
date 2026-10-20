import SwiftUI
import AppKit

enum Palette {
    static let ink = adaptive(light: NSColor(red: 0.16, green: 0.23, blue: 0.20, alpha: 1),
                              dark: NSColor(red: 0.90, green: 0.95, blue: 0.91, alpha: 1))
    static let green = adaptive(light: NSColor(red: 0.22, green: 0.43, blue: 0.33, alpha: 1),
                                dark: NSColor(red: 0.57, green: 0.79, blue: 0.65, alpha: 1))
    static let mint = adaptive(light: NSColor(red: 0.89, green: 0.94, blue: 0.89, alpha: 1),
                               dark: NSColor(red: 0.19, green: 0.29, blue: 0.23, alpha: 1))
    static let paper = adaptive(light: NSColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1),
                                dark: NSColor(red: 0.12, green: 0.15, blue: 0.13, alpha: 1))
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.065)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

struct AppMark: View {
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: "viewfinder")
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(Palette.green)
            .frame(width: size, height: size)
            .background(Palette.mint, in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.tinyLiquidGlass) private var glass
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 15).padding(.vertical, 10)
            .foregroundStyle(glass ? Palette.ink : .white)
            .tinySurface(glass: glass, radius: 9,
                         fill: glass ? Palette.mint : Palette.green.opacity(configuration.isPressed ? 0.8 : 1),
                         interactive: true, tint: Palette.green.opacity(0.18))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButton: ButtonStyle {
    @Environment(\.tinyLiquidGlass) private var glass
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(Palette.ink)
            .tinySurface(glass: glass, radius: 9, fill: Color.primary.opacity(configuration.isPressed ? 0.08 : 0.035), interactive: true)
    }
}

struct ShelfHeaderButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.ink)
            .background(Palette.card.opacity(configuration.isPressed ? 0.8 : 0.45),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1).allowsHitTesting(false))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct DashboardView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var store: ShotStore
    let showShelf: () -> Void
    let chooseFolder: () -> Void
    let openScreenshotOptions: () -> Void
    private var selection: Int { store.selectedPage }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    AppMark()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TinyShot").font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("留住，刚刚那一刻").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }.padding(.top, 36).padding(.bottom, 43)
                nav("概览", icon: "square.grid.2x2", index: 0)
                nav("偏好设置", icon: "slider.horizontal.3", index: 1)
                Spacer()
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Circle().fill(store.monitoring ? Palette.green : Color.orange).frame(width: 6, height: 6)
                        Text(store.monitoring ? "正在等待你的下一张截图" : "需要设置截图文件夹")
                            .font(.system(size: 10, weight: .medium))
                    }
                    Text("本地运行 · 图片不会上传")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.padding(.bottom, 24)
                Divider().overlay(Palette.line)
                HStack { Text("为顺手而生"); Spacer(); Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")") }
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.vertical, 19)
            }.padding(.horizontal, 22).frame(width: 204)
                .background(store.liquidGlassEnabled ? .clear : Color(red: 0.94, green: 0.95, blue: 0.92))
            Rectangle().fill(Palette.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Text(selection == 0 ? "你的截图，随时待命" : "按你的习惯来")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                        Spacer()
                        Label("菜单栏已就位", systemImage: "menubar.rectangle")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    if selection == 0 { overview } else { preferences }
                }.padding(32)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(store.liquidGlassEnabled ? .clear : Palette.paper)
        }
        .foregroundStyle(Palette.ink).frame(minWidth: 900, minHeight: 650)
        .clipShape(RoundedRectangle(cornerRadius: store.liquidGlassEnabled ? 24 : 12, style: .continuous))
        .tinySurface(glass: store.liquidGlassEnabled, radius: store.liquidGlassEnabled ? 24 : 12, fill: Palette.paper)
        .glassWindowRim(enabled: store.liquidGlassEnabled, radius: 24)
        // Cover the title-bar safe area as well, so the traffic lights sit
        // inside one continuous glass window instead of above a clear gap.
        .ignoresSafeArea()
        .preferredColorScheme(store.liquidGlassEnabled ? nil : .light)
        .environment(\.tinyLiquidGlass, store.liquidGlassEnabled)
        .overlay(alignment: .bottom) {
            if let notice = store.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule()).padding(.bottom, 20).shadow(color: .black.opacity(0.06), radius: 12)
            }
        }
    }

    private func nav(_ title: String, icon: String, index: Int) -> some View {
        Button { store.selectedPage = index } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 18)
                Text(title).font(.system(size: 12, weight: selection == index ? .semibold : .regular))
                Spacer()
                if index == 0, !store.shots.isEmpty {
                    Text("\(store.shots.count)").font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.7), in: Capsule())
                }
            }.foregroundStyle(selection == index ? Palette.green : Palette.muted)
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(selection == index ? Palette.mint : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).padding(.bottom, 6)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 15) {
                    Text("截下来。\n慢慢用。")
                        .font(.system(size: 40, weight: .semibold)).tracking(-1.8).lineSpacing(4)
                    Text("不必追着即将消失的缩略图。\n截图留在手边，用完再收起。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(7)
                    HStack(spacing: 6) {
                        ForEach(["⇧", "⌘", "4"], id: \.self) { key in
                            Text(key).font(.system(size: 15, weight: .medium))
                                .frame(width: 32, height: 30).background(.white, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line))
                        }
                        Text("还是熟悉的快捷键").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.leading, 5)
                    }.padding(.top, 2)
                }
                Spacer(minLength: 0)
                heroIllustration
            }.padding(.vertical, 6)
            HStack(spacing: 12) {
                feature("用完再走", detail: "成功拖放或复制后收起", icon: "pin")
                feature("直接拖给 AI", detail: "也能复制后 ⌘V 粘贴", icon: "cursorarrow.and.square.on.square.dashed")
                feature("多张都留着", detail: "接着截，之前的也还在", icon: "square.stack")
            }
            setupGuide
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("截图暂存").font(.system(size: 13, weight: .semibold))
                    Text("\(store.shots.count)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("打开悬浮窗", action: showShelf).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.green)
                }
                if store.shots.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 24, weight: .light)).foregroundStyle(Palette.muted)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("下一张截图，就从这里开始").font(.system(size: 12, weight: .medium))
                            Text("试着截一张，或先看看悬浮效果。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("试试示例") { store.addDemo() }.buttonStyle(SecondaryButton())
                    }.padding(20).frame(maxWidth: .infinity).background(Palette.card.opacity(store.liquidGlassEnabled ? 0.35 : 0.8), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    ForEach(store.shots.prefix(3)) { shot in
                        HStack(spacing: 12) {
                            if let image = store.image(for: shot) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 60, height: 38)
                                    .background(Palette.mint).clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(shot.isDemo ? "示例截图" : shot.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(shot.createdAt, style: .time).font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button("复制") { store.copy(shot) }.buttonStyle(SecondaryButton())
                        }.padding(10).background(Palette.card.opacity(store.liquidGlassEnabled ? 0.35 : 1), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            if !store.recent.isEmpty { recentSection }
        }
    }

    private var heroIllustration: some View {
        ZStack {
            Circle().fill(Palette.mint.opacity(0.7)).frame(width: 210, height: 210)
            RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.65))
                .frame(width: 187, height: 150).rotationEffect(.degrees(-9)).offset(x: -8, y: -2)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Circle().fill(Palette.green).frame(width: 5, height: 5)
                    Text("一张灵感，已留住").font(.system(size: 9, weight: .medium))
                    Spacer()
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Palette.green)
                }
                Image(nsImage: NSImage(data: DemoImage.png())!).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Text("拖到你需要的地方").font(.system(size: 8)).foregroundStyle(Palette.muted)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Palette.green)
                }
            }.padding(13).frame(width: 195).background(.white, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line))
                .shadow(color: Palette.green.opacity(0.12), radius: 16, x: 0, y: 10).rotationEffect(.degrees(5))
            Image(systemName: "cursorarrow").font(.system(size: 29, weight: .medium)).foregroundStyle(Palette.green)
                .shadow(color: .white, radius: 2).offset(x: 70, y: 78)
        }.frame(width: 230, height: 220).accessibilityLabel("截图会持续保留在 TinyShot 悬浮窗")
    }

    private func feature(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 17, weight: .regular)).foregroundStyle(Palette.green).frame(height: 23)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
            .background(Palette.card.opacity(store.liquidGlassEnabled ? 0.30 : 0.7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
    }

    private var setupGuide: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "sparkle").foregroundStyle(Palette.green)
                Text("第一次使用，花 10 秒设置一下").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            HStack(alignment: .top, spacing: 10) {
                Text("01").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.green)
                VStack(alignment: .leading, spacing: 5) {
                    Text("关闭系统的「显示浮动缩略图」").font(.system(size: 11, weight: .medium))
                    Text("按 ⇧⌘5 → 选项，取消勾选。省去系统预览的等待，由 TinyShot 显示截图。")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                }
                Spacer(minLength: 0)
                Button("打开截图选项", action: openScreenshotOptions).buttonStyle(SecondaryButton())
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                Text("02").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.green)
                VStack(alignment: .leading, spacing: 5) {
                    Text("确认截图保存位置").font(.system(size: 11, weight: .medium))
                    Text(store.folder.path).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("选择文件夹", action: chooseFolder).buttonStyle(SecondaryButton())
            }
            if let error = store.monitorError {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.orange)
            }
        }.padding(17).background(Palette.mint.opacity(store.liquidGlassEnabled ? 0.25 : 0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("让截图，多等你一会。")
                .font(.system(size: 28, weight: .semibold)).tracking(-0.8)
            Text("轻一点，顺手一点。其他交给 TinyShot。")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 0) {
                settingRow("液态玻璃", detail: glassDescription) {
                    Toggle("液态玻璃", isOn: $store.liquidGlassEnabled).labelsHidden().toggleStyle(.switch).tint(Palette.green)
                        .help("立即切换托盘和主窗口外观，并记住此选择")
                }
                Divider()
                settingRow("使用后自动收起", detail: "复制成功，或目标软件接受拖放后收起卡片。") {
                    Toggle("使用后自动收起", isOn: $store.autoDismiss).labelsHidden().toggleStyle(.switch).tint(Palette.green)
                }
                Divider()
                settingRow("拖出后删除原图", detail: "成功拖放后直接删除，不进废纸篓。复制与取消不删除。") {
                    Toggle("拖出后删除原图", isOn: $store.deleteAfterDrag).labelsHidden().toggleStyle(.switch).tint(Palette.green)
                }
                Divider()
                settingRow("悬浮保留时间", detail: "到时只收起卡片，原始截图仍保留。") {
                    Picker("保留时间", selection: $store.retention) {
                        ForEach(Retention.allCases) { option in Text(option.title).tag(option) }
                    }.labelsHidden().frame(width: 170)
                }
                Divider()
                settingRow("截图文件夹", detail: store.folder.path) {
                    Button("更改…", action: chooseFolder).buttonStyle(SecondaryButton())
                }
            }.padding(.horizontal, 18).background(Palette.card.opacity(store.liquidGlassEnabled ? 0.35 : 1), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
            Text("卡片右上角 × 会同时删除截图文件；顶部“收起”仅隐藏暂存窗。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            setupGuide
            Label("截图只在本机处理，不会自动上传或修改系统截图设置。点击 × 或开启拖出后删除时会直接删除原图，无法通过废纸篓恢复。", systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(5)
            Text("拖放被接受不代表 AI 已完成上传；请以目标软件的上传状态为准。")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var glassDescription: String {
        if reduceTransparency { return "系统已开启“降低透明度”，将优先保证清晰可读。" }
        if SurfaceRendering.nativeAvailable { return "托盘和主窗口使用系统液态玻璃，切换立即生效。" }
        return "当前系统使用磨砂效果；macOS 26 及以上支持原生液态玻璃。"
    }

    private func settingRow<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            content()
        }.padding(.vertical, 20)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近收起").font(.system(size: 13, weight: .semibold))
            ForEach(store.recent.prefix(4)) { shot in
                HStack {
                    Image(systemName: "photo").foregroundStyle(Palette.muted)
                    Text(shot.isDemo ? "示例截图" : shot.name).font(.system(size: 11)).lineLimit(1)
                    Spacer()
                    Button("放回暂存") { store.restore(shot) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.green)
                }.padding(12).background(Palette.card.opacity(store.liquidGlassEnabled ? 0.35 : 1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct ShelfView: View {
    @ObservedObject var store: ShotStore
    let hide: () -> Void
    let openSettings: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AppMark(size: 25)
                Text("截图暂存").font(.system(size: 12, weight: .semibold))
                Text("\(store.shots.count)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13))
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }.buttonStyle(ShelfHeaderButton()).accessibilityLabel("偏好设置").help("偏好设置")
                Button(action: hide) {
                    Label("收起", systemImage: "minus").font(.system(size: 11, weight: .medium))
                        .frame(minWidth: 64, minHeight: 32).contentShape(Rectangle())
                }.buttonStyle(ShelfHeaderButton()).accessibilityLabel("收起截图暂存")
                    .help("隐藏暂存窗，截图继续保留；点击菜单栏图标可再次打开")
            }.foregroundStyle(Palette.ink).padding(.horizontal, 15).padding(.vertical, 10)
            Rectangle().fill(Palette.line).frame(height: 1)
            if store.shots.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "viewfinder").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(Palette.green)
                    Text("截图后，在这里等你").font(.system(size: 13, weight: .medium))
                    Text("⇧⌘4 截图 · 拖走或复制后收起").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Button("试试示例") { store.addDemo() }.buttonStyle(SecondaryButton()).padding(.top, 3)
                }.frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.shots) { shot in ShotCard(store: store, shot: shot) }
                    }.padding(12)
                }.frame(height: min(CGFloat(store.shots.count) * 224 + 24, 504))
            }
            HStack(spacing: 5) {
                Image(systemName: "\(store.retention == .untilUsed ? "pin" : "clock")")
                Text(store.notice ?? (store.retention == .untilUsed ? "留到你用完，不着急。" : store.retention.title))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 15).padding(.vertical, 11)
        }.tinySurface(glass: store.liquidGlassEnabled, radius: ShelfMetrics.cornerRadius, fill: Palette.paper.opacity(0.98))
            // Native glass already draws its own rim; extra strokes here cause
            // multiple outlines around the floating window.
            .overlay {
                if !store.liquidGlassEnabled {
                    RoundedRectangle(cornerRadius: ShelfMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.8), lineWidth: 1).allowsHitTesting(false)
                }
            }
            .foregroundStyle(Palette.ink).preferredColorScheme(store.liquidGlassEnabled ? nil : .light)
            .environment(\.tinyLiquidGlass, store.liquidGlassEnabled)
            .frame(width: ShelfMetrics.width)
    }
}

struct ShotCard: View {
    @ObservedObject var store: ShotStore
    let shot: Shot
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                DraggableShot(shot: shot, image: store.image(for: shot),
                    prepareDrag: { try store.prepareDrag(shot) },
                    completeDrag: { transfer, accepted in store.completeDrag(transfer, accepted: accepted) },
                    onError: { store.toast("无法准备拖放，原图保持不变；请检查文件或访问权限") })
                    .frame(height: 144).frame(maxWidth: .infinity)
                    .background(Palette.mint.opacity(store.liquidGlassEnabled ? 0.30 : 1))
                    .accessibilityLabel("拖动\(shot.name)到其他软件")
                Button { store.deleteShot(shot) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.ink).frame(width: 22, height: 22).background(.regularMaterial, in: Circle())
                }.buttonStyle(.plain).padding(8)
                    .accessibilityLabel("删除截图")
                    .help("删除原图并移除卡片，不进废纸篓")
            }
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(shot.isDemo ? "示例截图" : shot.url.lastPathComponent)
                        .font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text("拖入 AI，或复制粘贴").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Button { NSWorkspace.shared.activateFileViewerSelecting([shot.url]) } label: {
                    Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }.buttonStyle(.plain).help("在访达中显示")
                Button { store.copy(shot) } label: { Label("复制", systemImage: "doc.on.doc") }
                    .buttonStyle(PrimaryButton()).help("复制图片；在目标软件中按 ⌘V")
            }.padding(11)
        }.background(Palette.card.opacity(store.liquidGlassEnabled ? 0.35 : 1), in: RoundedRectangle(cornerRadius: 11))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line))
    }
}
