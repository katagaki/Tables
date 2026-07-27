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

    var body: some View {
        Text(CellFormatter.displayText(for: cell))
            .font(cell.style.font(zoom: zoom))
            .foregroundStyle(textColor)
            .underline(cell.style.isUnderlined)
            .strikethrough(cell.style.isStruckThrough)
            .multilineTextAlignment(textAlignment)
            .lineLimit(cell.style.wrapsText ? nil : 1)
            .truncationMode(.tail)
            .padding(.horizontal, 6 * zoom)
            .padding(.vertical, 2 * zoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
            .background(cell.style.fillColor(for: colorScheme) ?? .clear)
            .overlay(CellBorderOverlay(style: cell.style, scheme: colorScheme))
            .contentShape(.rect)
    }
}

/// Draws the sheet's hairline separators plus any explicit cell borders.
private struct CellBorderOverlay: View {
    let style: CellStyle
    let scheme: ColorScheme

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

                if !style.borders.isEmpty {
                    Path { path in
                        if style.borders.contains(.top) {
                            path.move(to: .zero)
                            path.addLine(to: CGPoint(x: size.width, y: 0))
                        }
                        if style.borders.contains(.bottom) {
                            path.move(to: CGPoint(x: 0, y: size.height))
                            path.addLine(to: CGPoint(x: size.width, y: size.height))
                        }
                        if style.borders.contains(.leading) {
                            path.move(to: .zero)
                            path.addLine(to: CGPoint(x: 0, y: size.height))
                        }
                        if style.borders.contains(.trailing) {
                            path.move(to: CGPoint(x: size.width, y: 0))
                            path.addLine(to: CGPoint(x: size.width, y: size.height))
                        }
                    }
                    .stroke(style.borderColor(for: scheme), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

extension Color {
    /// The hairline between cells — `primary` so it tracks the appearance.
    static let gridLine = Color.primary.opacity(0.12)
    static let headerBackground = Color.primary.opacity(0.05)
}
