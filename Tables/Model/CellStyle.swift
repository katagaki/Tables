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
        case .automatic: return String(localized: "Alignment.Horizontal.Automatic")
        case .leading: return String(localized: "Alignment.Horizontal.Left")
        case .center: return String(localized: "Alignment.Horizontal.Center")
        case .trailing: return String(localized: "Alignment.Horizontal.Right")
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

    var label: String {
        switch self {
        case .top: return String(localized: "Alignment.Vertical.Top")
        case .middle: return String(localized: "Alignment.Vertical.Middle")
        case .bottom: return String(localized: "Alignment.Vertical.Bottom")
        }
    }

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

/// A single side of a cell's border box, as a discrete case rather than a set.
///
/// `BorderEdges` stays the API the formatting UI works in, but a per-edge line
/// style and colour need a hashable key, and an OptionSet member is a poor one.
enum BorderEdge: String, Hashable, Sendable, CaseIterable {
    case top, leading, bottom, trailing

    /// The matching `BorderEdges` member, for bridging between the two.
    var edges: BorderEdges {
        switch self {
        case .top: return .top
        case .leading: return .leading
        case .bottom: return .bottom
        case .trailing: return .trailing
        }
    }

    /// The OOXML element name for this side inside `<border>`.
    var ooxmlTag: String {
        switch self {
        case .top: return "top"
        case .leading: return "left"
        case .bottom: return "bottom"
        case .trailing: return "right"
        }
    }
}

/// OOXML's `ST_BorderStyle` less `none`, which is modelled as the absence of a side.
///
/// Raw values are the OOXML tokens verbatim so reading and writing are a
/// straight `init(rawValue:)` / `rawValue` and no lossy mapping table is needed.
enum BorderLineStyle: String, Hashable, Sendable, CaseIterable {
    case hair, thin, medium, thick, double
    case dotted, dashed, dashDot, dashDotDot
    case mediumDashed, mediumDashDot, mediumDashDotDot, slantDashDot

    /// Stroke width in points at 100% zoom.
    var lineWidth: Double {
        switch self {
        case .hair: return 0.5
        case .thin, .dotted, .dashed, .dashDot, .dashDotDot: return 1
        case .medium, .mediumDashed, .mediumDashDot, .mediumDashDotDot, .slantDashDot: return 2
        case .thick: return 3
        case .double: return 1
        }
    }

    /// Dash lengths in points, empty for a solid stroke.
    var dashPattern: [Double] {
        switch self {
        case .dotted: return [1, 2]
        case .dashed: return [3, 2]
        case .dashDot: return [4, 2, 1, 2]
        case .dashDotDot: return [4, 2, 1, 2, 1, 2]
        case .mediumDashed: return [4, 3]
        case .mediumDashDot: return [5, 3, 1, 3]
        case .mediumDashDotDot: return [5, 3, 1, 3, 1, 3]
        case .slantDashDot: return [5, 2, 1, 2]
        default: return []
        }
    }

    /// A double rule is drawn as two thin strokes this far apart, in points.
    var doubleLineGap: Double? { self == .double ? 2 : nil }

    var label: String {
        switch self {
        case .hair: return String(localized: "BorderLineStyle.Hairline")
        case .thin: return String(localized: "BorderLineStyle.Thin")
        case .medium: return String(localized: "BorderLineStyle.Medium")
        case .thick: return String(localized: "BorderLineStyle.Thick")
        case .double: return String(localized: "BorderLineStyle.Double")
        case .dotted: return String(localized: "BorderLineStyle.Dotted")
        case .dashed: return String(localized: "BorderLineStyle.Dashed")
        case .dashDot: return String(localized: "BorderLineStyle.DashDot")
        case .dashDotDot: return String(localized: "BorderLineStyle.DashDotDot")
        case .mediumDashed: return String(localized: "BorderLineStyle.MediumDashed")
        case .mediumDashDot: return String(localized: "BorderLineStyle.MediumDashDot")
        case .mediumDashDotDot: return String(localized: "BorderLineStyle.MediumDashDotDot")
        case .slantDashDot: return String(localized: "BorderLineStyle.SlantDashDot")
        }
    }
}

/// Which part of a cell's border box a formatting change addresses.
///
/// OOXML gives every side its own style and colour, so "the border colour" is
/// not a single value — this is how the formatting UI says which sides it means.
enum BorderScope: String, Hashable, Identifiable, CaseIterable, Sendable {
    case all, top, leading, bottom, trailing, diagonal

    var id: String { rawValue }

    init(_ edge: BorderEdge) {
        switch edge {
        case .top: self = .top
        case .leading: self = .leading
        case .bottom: self = .bottom
        case .trailing: self = .trailing
        }
    }

    /// The box edge this scope names, or nil for `all` and `diagonal`.
    var edge: BorderEdge? {
        switch self {
        case .top: return .top
        case .leading: return .leading
        case .bottom: return .bottom
        case .trailing: return .trailing
        case .all, .diagonal: return nil
        }
    }

    var label: String {
        switch self {
        case .all: return String(localized: "Format.Border.Scope.All")
        case .top: return String(localized: "Format.Border.Top")
        case .leading: return String(localized: "Format.Border.Left")
        case .bottom: return String(localized: "Format.Border.Bottom")
        case .trailing: return String(localized: "Format.Border.Right")
        case .diagonal: return String(localized: "Format.Border.Scope.Diagonal")
        }
    }
}

/// One drawn border stroke: how it looks and what colour it is.
struct BorderSide: Hashable, Sendable {
    var lineStyle: BorderLineStyle = .thin
    /// OOXML "AARRGGBB". `nil` means the generator left the colour to the reader.
    var colorHex: String?
}

/// The `<diagonal>` rule, which is independent of the four box edges.
struct DiagonalBorder: Hashable, Sendable {
    var lineStyle: BorderLineStyle = .thin
    var colorHex: String?
    /// Runs from the bottom-left corner to the top-right one.
    var goesUp = false
    /// Runs from the top-left corner to the bottom-right one.
    var goesDown = false

    /// A diagonal with neither direction set draws nothing, which is how Excel
    /// stores a `<diagonal>` whose style was cleared but whose element remains.
    var isVisible: Bool { goesUp || goesDown }
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
    /// Per-edge line style and colour. An absent key means that edge has no rule.
    var borderSides: [BorderEdge: BorderSide] = [:]
    var diagonalBorder: DiagonalBorder?
    /// Indent steps, each roughly three characters of padding on the text's leading edge.
    var indent: Int = 0
    /// OOXML text rotation: 0–90 is counter-clockwise degrees, 91–180 is
    /// clockwise as `value - 90`, and 255 means the glyphs stack vertically.
    var textRotation: Int = 0

    /// The rotation value OOXML reserves for stacked (top-to-bottom) text.
    static let stackedTextRotation = 255

    static let `default` = CellStyle()

    var isDefault: Bool { self == CellStyle.default }

    /// Which edges carry a rule, as the OptionSet the formatting UI works in.
    ///
    /// Assigning through this drops any per-edge line style, which is what the
    /// UI's "toggle this edge on" gesture means; per-edge detail survives every
    /// read that does not go on to write.
    var borders: BorderEdges {
        get {
            BorderEdge.allCases.reduce(into: BorderEdges()) { result, edge in
                if borderSides[edge] != nil { result.insert(edge.edges) }
            }
        }
        set {
            let inheritedColor = borderColorHex
            for edge in BorderEdge.allCases {
                if newValue.contains(edge.edges) {
                    if borderSides[edge] == nil {
                        borderSides[edge] = BorderSide(lineStyle: .thin, colorHex: inheritedColor)
                    }
                } else {
                    borderSides[edge] = nil
                }
            }
        }
    }

    /// The border colour shared by the whole cell.
    ///
    /// OOXML colours each side separately, so this reports the first side that
    /// has one and, when assigned, repaints every side that exists. Callers that
    /// need true per-edge colour should go through `borderSides`.
    var borderColorHex: String? {
        get {
            for edge in BorderEdge.allCases {
                if let color = borderSides[edge]?.colorHex { return color }
            }
            return diagonalBorder?.colorHex
        }
        set {
            for edge in BorderEdge.allCases where borderSides[edge] != nil {
                borderSides[edge]?.colorHex = newValue
            }
            diagonalBorder?.colorHex = newValue
        }
    }

    // MARK: - Scoped border editing

    /// The line style in force for a scope.
    ///
    /// `all` answers from a fixed edge order rather than from the dictionary's,
    /// so a cell whose sides disagree reports the same one every time it is
    /// asked instead of flickering between them.
    func lineStyle(in scope: BorderScope) -> BorderLineStyle? {
        switch scope {
        case .diagonal: return diagonalBorder?.lineStyle
        case .all:
            return BorderEdge.allCases.compactMap { borderSides[$0]?.lineStyle }.first
                ?? diagonalBorder?.lineStyle
        default: return scope.edge.flatMap { borderSides[$0]?.lineStyle }
        }
    }

    func colorHex(in scope: BorderScope) -> String? {
        switch scope {
        case .diagonal: return diagonalBorder?.colorHex
        case .all: return borderColorHex
        default: return scope.edge.flatMap { borderSides[$0]?.colorHex }
        }
    }

    /// Draws or clears a set of edges, together.
    ///
    /// New sides inherit whatever style and colour the cell's other borders
    /// already carry, so adding an edge to a thick red box gets a thick red edge
    /// rather than a stray thin black one. Existing sides keep their own detail.
    mutating func toggleBorder(_ edges: BorderEdges) {
        let isTurningOff = borders.isSuperset(of: edges)
        let inherited = BorderSide(lineStyle: lineStyle(in: .all) ?? .thin, colorHex: borderColorHex)
        for edge in BorderEdge.allCases where edges.contains(edge.edges) {
            borderSides[edge] = isTurningOff ? nil : (borderSides[edge] ?? inherited)
        }
    }

    /// Sets the line style for a scope, raising the rule where there was none:
    /// choosing how a side should look is asking for that side. `all` is the
    /// exception — it restyles what is already drawn rather than boxing the cell.
    mutating func setLineStyle(_ value: BorderLineStyle, in scope: BorderScope) {
        switch scope {
        case .all:
            for edge in BorderEdge.allCases where borderSides[edge] != nil {
                borderSides[edge]?.lineStyle = value
            }
            diagonalBorder?.lineStyle = value
        case .diagonal:
            if diagonalBorder?.isVisible == true {
                diagonalBorder?.lineStyle = value
            } else {
                diagonalBorder = DiagonalBorder(
                    lineStyle: value, colorHex: borderColorHex, goesDown: true
                )
            }
        default:
            guard let edge = scope.edge else { return }
            var side = borderSides[edge] ?? BorderSide(colorHex: borderColorHex)
            side.lineStyle = value
            borderSides[edge] = side
        }
    }

    /// Sets — or, with nil, clears — the colour for a scope. Clearing never
    /// raises a rule that was not already there.
    mutating func setColorHex(_ value: String?, in scope: BorderScope) {
        switch scope {
        case .all:
            borderColorHex = value
        case .diagonal:
            diagonalBorder?.colorHex = value
        default:
            guard let edge = scope.edge else { return }
            if borderSides[edge] != nil {
                borderSides[edge]?.colorHex = value
            } else if value != nil {
                borderSides[edge] = BorderSide(
                    lineStyle: lineStyle(in: .all) ?? .thin, colorHex: value
                )
            }
        }
    }

    /// Turns the diagonal rule on or off, keeping whatever style it already had
    /// and clearing it outright once neither direction is wanted.
    mutating func setDiagonal(up: Bool, down: Bool) {
        guard up || down else {
            diagonalBorder = nil
            return
        }
        var diagonal = diagonalBorder ?? DiagonalBorder(colorHex: borderColorHex)
        diagonal.goesUp = up
        diagonal.goesDown = down
        diagonalBorder = diagonal
    }

    var textColor: Color? { Color(argbHex: textColorHex) }
    var fillColor: Color? { Color(argbHex: fillColorHex) }
    var borderColor: Color { Color(argbHex: borderColorHex) ?? .secondary }

    /// Leading padding the indent steps add, in points at 100% zoom. OOXML
    /// defines a step as about three characters, so it tracks the font size.
    var indentPoints: Double { Double(indent) * fontSize * 1.5 }

    /// True when the cell's glyphs should be stacked one above the next.
    var isTextStacked: Bool { textRotation == CellStyle.stackedTextRotation }

    /// Rotation in degrees counter-clockwise, with OOXML's split range flattened.
    var rotationDegrees: Double {
        guard !isTextStacked else { return 0 }
        let clamped = min(max(textRotation, 0), 180)
        return clamped <= 90 ? Double(clamped) : -Double(clamped - 90)
    }

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
        case .general: return String(localized: "NumberFormat.Preset.Automatic")
        case .number: return String(localized: "NumberFormat.Preset.Number")
        case .numberTwoPlaces: return String(localized: "NumberFormat.Preset.NumberTwoPlaces")
        case .thousands: return String(localized: "NumberFormat.Preset.Thousands")
        case .currency: return String(localized: "NumberFormat.Preset.Currency")
        case .accounting: return String(localized: "NumberFormat.Preset.Accounting")
        case .percent: return String(localized: "NumberFormat.Preset.Percentage")
        case .percentTwoPlaces: return String(localized: "NumberFormat.Preset.PercentageTwoPlaces")
        case .scientific: return String(localized: "NumberFormat.Preset.Scientific")
        case .date: return String(localized: "NumberFormat.Preset.Date")
        case .time: return String(localized: "NumberFormat.Preset.Time")
        case .dateTime: return String(localized: "NumberFormat.Preset.DateTime")
        case .text: return String(localized: "NumberFormat.Preset.Text")
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
