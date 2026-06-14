import SwiftUI

/// Uniform scale for a widget's content, derived from its panel size vs the
/// kind's default. 1 at the default size, growing as the user enlarges the
/// widget, so the numbers, charts, and chrome all grow together instead of a
/// fixed-size card stranded in a big empty panel.
private struct WidgetScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var widgetScale: CGFloat {
        get { self[WidgetScaleKey.self] }
        set { self[WidgetScaleKey.self] = newValue }
    }
}

/// The scale to use for a panel of `size`, clamped so content never collapses or
/// balloons. Uniform (min of the two axes) so nothing distorts when the aspect
/// ratio changes.
func widgetScale(for size: CGSize, default def: CGSize) -> CGFloat {
    guard def.width > 0, def.height > 0 else { return 1 }
    let ratio = min(size.width / def.width, size.height / def.height)
    return min(max(ratio, 0.85), 3)
}

/// A system font whose point size tracks the ambient `widgetScale`.
private struct ScaledFontModifier: ViewModifier {
    @Environment(\.widgetScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// Like `.font(.system(size:weight:design:))`, but the size scales with the
    /// widget. Use this for every widget label/number so resizing stays crisp
    /// (real fonts, not a blurry `scaleEffect`).
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }
}
