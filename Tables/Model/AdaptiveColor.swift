import SwiftUI

/// Adapts document colours to the current appearance.
///
/// Workbook colours are stored exactly as authored, so a spreadsheet written in
/// light mode is full of near-white fills and near-black text. Rather than
/// inverting everything — which would turn a brand red into cyan — this keeps
/// hue and saturation and only moves lightness, and only when it needs to:
///
/// - Near-greys (whitish/blackish) flip their lightness, so white paper becomes
///   dark paper and black ink becomes light ink.
/// - Saturated colours keep their identity and are nudged only far enough to
///   stay legible against the current background.
enum AdaptiveColor {
    /// Below this saturation a colour counts as "whitish or blackish".
    private static let achromaticThreshold = 0.14

    static func resolve(hex: String?, for scheme: ColorScheme, isText: Bool) -> Color? {
        guard let components = HSL(argbHex: hex) else { return nil }
        return Color(adjust(components, for: scheme, isText: isText))
    }

    private static func adjust(_ color: HSL, for scheme: ColorScheme, isText: Bool) -> HSL {
        guard scheme == .dark else { return color }
        var result = color

        if color.saturation < achromaticThreshold {
            // Whitish and blackish: flip lightness, keeping any slight tint.
            result.lightness = 1 - color.lightness
            return result
        }

        // Saturated: preserve the hue, lift or drop only for contrast.
        if isText {
            result.lightness = max(color.lightness, 0.62)
            result.saturation = min(color.saturation, 0.85)
        } else {
            // Fills sit behind text, so they stay deep enough to read against.
            result.lightness = min(color.lightness, 0.34)
        }
        return result
    }
}

/// A minimal HSL representation, used only for appearance adaptation.
private struct HSL {
    var hue: Double
    var saturation: Double
    var lightness: Double
    var alpha: Double

    init?(argbHex hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 6 { text = "FF" + text }
        guard text.count == 8, let raw = UInt32(text, radix: 16) else { return nil }

        let red = Double((raw >> 16) & 0xFF) / 255
        let green = Double((raw >> 8) & 0xFF) / 255
        let blue = Double(raw & 0xFF) / 255
        alpha = Double((raw >> 24) & 0xFF) / 255

        let highest = max(red, green, blue)
        let lowest = min(red, green, blue)
        let span = highest - lowest
        lightness = (highest + lowest) / 2

        guard span > 0 else {
            hue = 0
            saturation = 0
            return
        }
        saturation = lightness > 0.5 ? span / (2 - highest - lowest) : span / (highest + lowest)

        let sector: Double
        switch highest {
        case red: sector = (green - blue) / span + (green < blue ? 6 : 0)
        case green: sector = (blue - red) / span + 2
        default: sector = (red - green) / span + 4
        }
        hue = sector / 6
    }
}

private extension Color {
    init(_ components: HSL) {
        let (red, green, blue) = Color.rgb(from: components)
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: components.alpha)
    }

    static func rgb(from components: HSL) -> (Double, Double, Double) {
        guard components.saturation > 0 else {
            return (components.lightness, components.lightness, components.lightness)
        }
        let q = components.lightness < 0.5
            ? components.lightness * (1 + components.saturation)
            : components.lightness + components.saturation - components.lightness * components.saturation
        let p = 2 * components.lightness - q

        func channel(_ offset: Double) -> Double {
            var t = components.hue + offset
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return (channel(1.0 / 3), channel(0), channel(-1.0 / 3))
    }
}

extension CellStyle {
    func textColor(for scheme: ColorScheme) -> Color? {
        AdaptiveColor.resolve(hex: textColorHex, for: scheme, isText: true)
    }

    func fillColor(for scheme: ColorScheme) -> Color? {
        AdaptiveColor.resolve(hex: fillColorHex, for: scheme, isText: false)
    }

    func borderColor(for scheme: ColorScheme) -> Color {
        AdaptiveColor.resolve(hex: borderColorHex, for: scheme, isText: true) ?? .secondary
    }
}
