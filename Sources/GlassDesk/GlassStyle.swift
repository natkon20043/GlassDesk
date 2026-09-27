import SwiftUI

/// The bright specular edge that makes the Dock read as a "ring" of glass. Liquid Glass
/// already draws a faint rim; this strengthens it so the outline is visible on any wallpaper.
struct GlassRim<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [.white.opacity(0.55), .white.opacity(0.10), .white.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 0.8
        )
        .allowsHitTesting(false)
    }
}

/// Imitates Liquid Glass's pressed state, where light floods through the glass instead of
/// being frosted: a soft additive wash from the top-left plus a brighter inner edge. It sits
/// between the glass and the widget's content, and is static, so it costs nothing per frame.
private struct LightGlow<S: InsettableShape>: View {
    let shape: S
    let width: CGFloat

    var body: some View {
        ZStack {
            shape.fill(RadialGradient(colors: [.white.opacity(0.24), .white.opacity(0.07), .clear],
                                      center: UnitPoint(x: 0.25, y: 0), startRadius: 0, endRadius: width * 0.95))
            shape.strokeBorder(.white.opacity(0.18), lineWidth: 2)
                .blur(radius: 2)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

/// A rounded Liquid Glass card, the shared chrome for every desktop widget.
struct GlassCard<Content: View>: View {
    static var cornerRadius: CGFloat { 28 }

    var width: CGFloat = 320
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        let settings = Settings.shared
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        content
            .padding(padding)
            .frame(width: width, alignment: .leading)
            .background {
                if settings.glowEnabled { LightGlow(shape: shape, width: width) }
            }
            .contentShape(shape)
            .glassEffect(settings.glass.interactive(), in: shape)
            .overlay {
                if settings.ringEnabled { GlassRim(shape: shape) }
            }
    }
}
