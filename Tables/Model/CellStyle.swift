import Foundation
import SwiftUI

enum HorizontalTextAlignment: String, Hashable, Sendable, CaseIterable {
    case automatic, leading, center, trailing

    var symbolName: String {
        switch self {
        case .automatic: return "text.alignleft"
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }
}

enum VerticalTextAlignment: String, Hashable, Sendable, CaseIterable {
    case top, middle, bottom

    var symbolName: String {
        switch self {
        case .top: return "arrow.up.to.line"
        case .middle: return "arrow.down.and.line.horizontal.and.arrow.up"
        case .bottom: return "arrow.down.to.line"
        }
    }

    var label: String { rawValue.capitalized }

    var alignment: Alignment {
        switch self {
        case .top: return .top
        case .middle: return .center
        case .bottom: return .bottom
        }
    }
}

struct BorderEdges: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let top = BorderEdges(rawValue: 1 << 0)
    static let leading = BorderEdges(rawValue: 1 << 1)
    static let bottom = BorderEdges(rawValue: 1 << 2)
    static let trailing = BorderEdges(rawValue: 1 << 3)
    static let all: BorderEdges = [.top, .leading, .bottom, .trailing]
}

/// Visual formatting for a single cell. Colors are stored as OOXML "AARRGGBB" hex.
struct CellStyle: Hashable, Sendable {
    var isBold = false
    var isItalic = false
    var isUnderlined = false
    var isStruckThrough = false
    var fontSize: Double = 12
    var fontName: String = "Helvetica Neue"
    var textColorHex: String?
    var fillColorHex: String?
    var horizontalAlignment: HorizontalTextAlignment = .automatic
    var verticalAlignment: VerticalTextAlignment = .middle
    var wrapsText = false
    var numberFormat: String = NumberFormatPreset.general.code
    var borders: BorderEdges = []
    var borderColorHex: String?

    static let `default` = CellStyle()

    var isDefault: Bool { self == CellStyle.default }

    var textColor: Color? { Color(argbHex: textColorHex) }
    var fillColor: Color? { Color(argbHex: fillColorHex) }
    var borderColor: Color { Color(argbHex: borderColorHex) ?? .secondary }

    func font(zoom: Double = 1) -> Font {
        var font = Font.system(size: fontSize * zoom)
        if isBold { font = font.bold() }
        if isItalic { font = font.italic() }
        return font
    }
}

/// The number format codes the formatting UI offers.
enum NumberFormatPreset: String, CaseIterable, Identifiable, Sendable {
    case general, number, numberTwoPlaces, thousands, currency, accounting
    case percent, percentTwoPlaces, scientific, date, time, dateTime, text

    var id: String { rawValue }

    var code: String {
        switch self {
        case .general: return "General"
        case .number: return "0"
        case .numberTwoPlaces: return "0.00"
        case .thousands: return "#,##0"
        case .currency: return "$#,##0.00"
        case .accounting: return "#,##0.00;(#,##0.00)"
        case .percent: return "0%"
        case .percentTwoPlaces: return "0.00%"
        case .scientific: return "0.00E+00"
        case .date: return "yyyy-mm-dd"
        case .time: return "h:mm:ss"
        case .dateTime: return "yyyy-mm-dd h:mm"
        case .text: return "@"
        }
    }

    var label: String {
        switch self {
        case .general: return "Automatic"
        case .number: return "Number"
        case .numberTwoPlaces: return "Number (2 dp)"
        case .thousands: return "Thousands"
        case .currency: return "Currency"
        case .accounting: return "Accounting"
        case .percent: return "Percentage"
        case .percentTwoPlaces: return "Percentage (2 dp)"
        case .scientific: return "Scientific"
        case .date: return "Date"
        case .time: return "Time"
        case .dateTime: return "Date & Time"
        case .text: return "Text"
        }
    }

    static func preset(forCode code: String) -> NumberFormatPreset? {
        allCases.first { $0.code == code }
    }
}

extension Color {
    /// Builds a color from an OOXML "AARRGGBB" (or "RRGGBB") hex string.
    init?(argbHex hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 6 { text = "FF" + text }
        guard text.count == 8, let raw = UInt32(text, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((raw >> 16) & 0xFF) / 255,
            green: Double((raw >> 8) & 0xFF) / 255,
            blue: Double(raw & 0xFF) / 255,
            opacity: Double((raw >> 24) & 0xFF) / 255
        )
    }

    /// "AARRGGBB" representation, for round-tripping through OOXML.
    var argbHex: String? {
        #if canImport(UIKit)
        typealias PlatformColor = UIColor
        #else
        typealias PlatformColor = NSColor
        #endif
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
        guard PlatformColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #else
        guard let converted = PlatformColor(self).usingColorSpace(.sRGB) else { return nil }
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        let components = [alpha, red, green, blue].map { UInt8(max(0, min(1, $0)) * 255) }
        return components.map { String(format: "%02X", $0) }.joined()
    }
}
