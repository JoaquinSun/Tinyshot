import SwiftUI
import AppKit

enum ShelfMetrics {
    // The window bounds match the visible surface; there is no outer backing
    // margin for the glass renderer to tint as a rectangular white surround.
    static let width: CGFloat = 336
    static let cornerRadius: CGFloat = 17
    static let frameOverhead: CGFloat = 89
}

final class ShelfHostingView: NSHostingView<ShelfView> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = ShelfMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
}

enum SurfaceRendering: Equatable {
    case solid, frosted, liquidGlass

    static func resolve(enabled: Bool, reduceTransparency: Bool, nativeAvailable: Bool) -> Self {
        guard enabled && !reduceTransparency else { return .solid }
        return nativeAvailable ? .liquidGlass : .frosted
    }

    static var nativeAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

private struct LiquidGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tinyLiquidGlass: Bool {
        get { self[LiquidGlassKey.self] }
        set { self[LiquidGlassKey.self] = newValue }
    }
}

struct AdaptiveSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let enabled: Bool
    let radius: CGFloat
    let solidFill: Color
    var interactive = false
    var tint: Color?

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch SurfaceRendering.resolve(enabled: enabled, reduceTransparency: reduceTransparency,
                                        nativeAvailable: SurfaceRendering.nativeAvailable) {
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        case .frosted:
            content.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.25)).allowsHitTesting(false))
        case .solid:
            content.background(solidFill, in: shape)
        }
    }
}

extension View {
    func tinySurface(glass: Bool, radius: CGFloat, fill: Color, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(AdaptiveSurface(enabled: glass, radius: radius, solidFill: fill, interactive: interactive, tint: tint))
    }

    func glassWindowRim(enabled: Bool, radius: CGFloat) -> some View {
        overlay {
            if enabled {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.18), .white.opacity(0.5)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: max(0, radius - 1), style: .continuous)
                            .inset(by: 1)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
