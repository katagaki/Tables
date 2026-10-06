import SwiftUI

/// The pieces of the document picker's top area: a green field ruled like a
/// sheet, the app's table glyph above the title, and a few cells of work
/// floating around it.
enum DocumentLaunch {
    /// The app icon's green, a little deeper at the foot so the white title and
    /// the system's buttons stay legible over it.
    static let topColor = Color(red: 0.16, green: 0.66, blue: 0.39)
    static let bottomColor = Color(red: 0.05, green: 0.40, blue: 0.22)
}

/// The green gradient, ruled with faint gridlines that fade out towards the
/// title so the page reads as a sheet without the lines competing with text.
struct DocumentLaunchBackground: View {
    private let cellSize = CGSize(width: 64, height: 26)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DocumentLaunch.topColor, DocumentLaunch.bottomColor],
                startPoint: .top,
                endPoint: .bottom
            )
            Canvas { context, size in
                var lines = Path()
                var x = 0.0
                while x <= size.width {
                    lines.move(to: CGPoint(x: x, y: 0))
                    lines.addLine(to: CGPoint(x: x, y: size.height))
                    x += cellSize.width
                }
                var y = 0.0
                while y <= size.height {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                    y += cellSize.height
                }
                context.stroke(lines, with: .color(.white.opacity(0.14)), lineWidth: 0.5)
            }
            .mask {
                LinearGradient(
                    colors: [.white, .white.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// The table glyph from the app icon — two columns by three rows, rounded
/// only at the outer corners — drawn above the title.
struct DocumentLaunchGlyph: View {
    /// Each cell's opacity, row by row, matching the icon artwork.
    private let opacities: [[Double]] = [[0.95, 0.55], [0.72, 0.95], [0.45, 0.78]]
    var cellSize = CGSize(width: 56, height: 30)
    var spacing = 3.0
    var cornerRadius = 9.0

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<2, id: \.self) { column in
                        UnevenRoundedRectangle(cornerRadii: corners(row: row, column: column))
                            .fill(.white.opacity(opacities[row][column]))
                            .frame(width: cellSize.width, height: cellSize.height)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func corners(row: Int, column: Int) -> RectangleCornerRadii {
        let top = row == 0, bottom = row == 2
        let leading = column == 0, trailing = column == 1
        return RectangleCornerRadii(
            topLeading: top && leading ? cornerRadius : 0,
            bottomLeading: bottom && leading ? cornerRadius : 0,
            bottomTrailing: bottom && trailing ? cornerRadius : 0,
            topTrailing: top && trailing ? cornerRadius : 0
        )
    }
}

/// The table glyph with a formula, a reference and a small chart set flat
/// around it, in the empty space beside the leading-aligned title.
/// Decoration only, so hidden from VoiceOver.
struct DocumentLaunchOverlay: View {
    let geometry: DocumentLaunchGeometryProxy

    var body: some View {
        // The title frame spans the title and the actions beneath it, so the
        // title's own line sits near its top. The scene centres in the band
        // from the top of the launch area down to that line, at the trailing
        // edge where a short title leaves room.
        let bandTop = geometry.frame.minY
        let bandBottom = geometry.titleViewFrame.minY + 90
        let center = CGPoint(
            x: geometry.frame.maxX - 96,
            y: (bandTop + bandBottom) / 2
        )

        ZStack {
            DocumentLaunchGlyph()
                .position(center)

            // The chips line up against the glyph's edges, 10pt clear of it:
            // the formula with its top, the reference with its bottom, and the
            // chart beneath it with its trailing edge.
            formulaChip
                .frame(width: 200, alignment: .trailing)
                .position(x: center.x - 168, y: center.y - 32)

            referenceChip
                .position(x: center.x - 90, y: center.y + 32)

            chartChip
                .position(x: center.x + 28, y: center.y + 81)
        }
        .accessibilityHidden(true)
    }

    private var formulaChip: some View {
        HStack(spacing: 6) {
            Text(verbatim: "fx")
                .font(.system(size: 12, weight: .semibold, design: .serif).italic())
                .foregroundStyle(.white.opacity(0.7))
            Text(verbatim: "=SUM(B2:B9)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.18), in: .capsule)
    }

    private var referenceChip: some View {
        Text(verbatim: "A1")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 44, height: 32)
            .background(.white.opacity(0.18), in: .rect(cornerRadius: 10))
    }

    private var chartChip: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach([0.45, 0.8, 0.6, 1.0], id: \.self) { height in
                Capsule()
                    .fill(.white.opacity(0.4 + height * 0.5))
                    .frame(width: 6, height: 22 * height)
            }
        }
        .frame(width: 60, height: 46)
        .background(.white.opacity(0.18), in: .rect(cornerRadius: 12))
    }
}
