import SwiftUI

/// One rendered cell.
///
/// Deliberately cheap and `Equatable`: the grid rebuilds these on every scroll
/// frame, and nothing about the selection reaches them — that is drawn as a
/// single overlay — so moving the selection never invalidates the whole grid.
struct GridCellView: View, Equatable {
    let cell: Cell
    let zoom: Double

    @Environment(\.colorScheme) private var colorScheme

    nonisolated static func == (lhs: GridCellView, rhs: GridCellView) -> Bool {
        lhs.cell == rhs.cell && lhs.zoom == rhs.zoom
    }

    private var alignment: HorizontalTextAlignment {
        cell.style.horizontalAlignment == .automatic
            ? CellFormatter.naturalAlignment(for: cell.value)
            : cell.style.horizontalAlignment
    }

    private var frameAlignment: Alignment {
        switch (alignment, cell.style.verticalAlignment) {
        case (.trailing, .top): return .topTrailing
        case (.trailing, .middle): return .trailing
        case (.trailing, .bottom): return .bottomTrailing
        case (.center, .top): return .top
        case (.center, .middle): return .center
        case (.center, .bottom): return .bottom
        case (_, .top): return .topLeading
        case (_, .middle): return .leading
        case (_, .bottom): return .bottomLeading
        }
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }

    private var textColor: Color {
        if cell.value.errorValue != nil { return .red }
        return cell.style.textColor(for: colorScheme) ?? .primary
    }

    /// Stacked text is drawn as one glyph per line rather than by rotating the
    /// run, which is what Excel's `textRotation="255"` actually looks like.
    private var displayText: String {
        let text = CellFormatter.displayText(for: cell)
        guard cell.style.isTextStacked else { return text }
        return text.map(String.init).joined(separator: "\n")
    }

    /// Indent pads the edge the text is aligned to, matching Excel.
    private var indentEdge: Edge.Set { alignment == .trailing ? .trailing : .leading }

    var body: some View {
        Text(displayText)
            .font(cell.style.font(zoom: zoom))
            .foregroundStyle(textColor)
            .underline(cell.style.isUnderlined)
            .strikethrough(cell.style.isStruckThrough)
            .multilineTextAlignment(textAlignment)
            .lineLimit(cell.style.wrapsText || cell.style.isTextStacked ? nil : 1)
            .truncationMode(.tail)
            // Rotation is applied before padding so the padded box, not the
            // glyphs, is what the cell frame aligns.
            .rotationEffect(.degrees(-cell.style.rotationDegrees))
            .padding(.horizontal, 6 * zoom)
            .padding(.vertical, 2 * zoom)
            .padding(indentEdge, cell.style.indentPoints * zoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
            .background(cell.style.fillColor(for: colorScheme) ?? .clear)
            .overlay(CellBorderOverlay(style: cell.style, scheme: colorScheme, zoom: zoom))
            .contentShape(.rect)
    }
}

/// Draws the sheet's hairline separators plus any explicit cell borders.
private struct CellBorderOverlay: View {
    let style: CellStyle
    let scheme: ColorScheme
    let zoom: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: size.width, y: 0))
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: size.height))
                }
                .stroke(Color.gridLine, lineWidth: 1)

                // Each edge gets its own stroke because line width, dash pattern
                // and colour all vary per edge in OOXML.
                ForEach(BorderEdge.allCases, id: \.self) { edge in
                    if let side = style.borderSides[edge] {
                        stroke(side.lineStyle, color: side.colorHex) { offset in
                            edgePath(edge, in: size, offset: offset)
                        }
                    }
                }

                if let diagonal = style.diagonalBorder, diagonal.isVisible {
                    stroke(diagonal.lineStyle, color: diagonal.colorHex) { offset in
                        diagonalPath(diagonal, in: size, offset: offset)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Strokes a line style, drawing a double rule as two offset passes.
    @ViewBuilder
    private func stroke(
        _ lineStyle: BorderLineStyle, color: String?, path: @escaping (Double) -> Path
    ) -> some View {
        let width = lineStyle.lineWidth * zoom
        let dash = lineStyle.dashPattern.map { CGFloat($0 * zoom) }
        let paint = AdaptiveColor.resolve(hex: color, for: scheme, isText: true) ?? .secondary
        let offsets: [Double] = lineStyle.doubleLineGap.map { [-$0 * zoom / 2, $0 * zoom / 2] } ?? [0]
        ForEach(Array(offsets.enumerated()), id: \.offset) { _, offset in
            path(offset).stroke(paint, style: StrokeStyle(lineWidth: width, dash: dash))
        }
    }

    /// One edge of the cell rectangle, nudged inwards by `offset` so that a
    /// double rule's two passes both land inside the cell.
    private func edgePath(_ edge: BorderEdge, in size: CGSize, offset: Double) -> Path {
        Path { path in
            switch edge {
            case .top:
                path.move(to: CGPoint(x: 0, y: offset + abs(offset)))
                path.addLine(to: CGPoint(x: size.width, y: offset + abs(offset)))
            case .bottom:
                path.move(to: CGPoint(x: 0, y: size.height + offset - abs(offset)))
                path.addLine(to: CGPoint(x: size.width, y: size.height + offset - abs(offset)))
            case .leading:
                path.move(to: CGPoint(x: offset + abs(offset), y: 0))
                path.addLine(to: CGPoint(x: offset + abs(offset), y: size.height))
            case .trailing:
                path.move(to: CGPoint(x: size.width + offset - abs(offset), y: 0))
                path.addLine(to: CGPoint(x: size.width + offset - abs(offset), y: size.height))
            }
        }
    }

    private func diagonalPath(_ diagonal: DiagonalBorder, in size: CGSize, offset: Double) -> Path {
        Path { path in
            if diagonal.goesDown {
                path.move(to: CGPoint(x: 0, y: offset))
                path.addLine(to: CGPoint(x: size.width, y: size.height + offset))
            }
            if diagonal.goesUp {
                path.move(to: CGPoint(x: 0, y: size.height + offset))
                path.addLine(to: CGPoint(x: size.width, y: offset))
            }
        }
    }
}

extension Color {
    /// The hairline between cells.
    ///
    /// Not one opacity of `primary` for both appearances: a hairline is thin
    /// enough that the eye needs far more contrast from it in the dark, where
    /// 12% white over black all but disappears, than the same figure gives
    /// over white paper.
    static let gridLine: Color = {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.32)
                : UIColor(white: 0, alpha: 0.14)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.32)
                : NSColor(white: 0, alpha: 0.14)
        })
        #endif
    }()

    static let headerBackground = Color.primary.opacity(0.05)
}
