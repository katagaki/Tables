import SwiftUI

/// The pieces of the document picker's top area: a green field ruled like a
/// sheet, with a wall of the app's features behind the actions.
enum DocumentLaunch {
    /// A wash of the app icon's green, kept quiet: near white in light mode,
    /// near black in dark, so the system's buttons and browser read over it
    /// and the colour stays a backdrop rather than the whole page.
    static let topColor = adaptive(
        light: UIColor(red: 0.86, green: 0.95, blue: 0.89, alpha: 1),
        dark: UIColor(red: 0.07, green: 0.20, blue: 0.13, alpha: 1)
    )
    static let bottomColor = adaptive(
        light: UIColor(red: 0.95, green: 0.98, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.04, green: 0.09, blue: 0.06, alpha: 1)
    )
    /// The colour the gridlines are drawn in.
    static let ink = adaptive(
        light: UIColor(red: 0.10, green: 0.56, blue: 0.31, alpha: 1),
        dark: UIColor(red: 0.66, green: 0.90, blue: 0.75, alpha: 1)
    )

    /// Where the middle of the header sits. The scene's title is left empty,
    /// but its frame still starts where that title would, with the actions
    /// about 100pt below; the line runs a little above halfway down that gap.
    static func headerLine(in geometry: DocumentLaunchGeometryProxy) -> Double {
        geometry.titleViewFrame.minY + 40
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// The green wash, ruled with faint gridlines that fade out towards the
/// browser so the page reads as a sheet without the lines competing with text.
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
                context.stroke(lines, with: .color(DocumentLaunch.ink.opacity(0.12)), lineWidth: 0.5)
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

/// A wall of small tiles, each something a workbook can hold — values,
/// formulas, charts, comments, macros, form controls and pictures — laid in
/// staggered rows across the whole header. It sits behind
/// the buttons, faded so it reads as a backdrop rather than content.
/// Decoration only, so hidden from VoiceOver.
struct DocumentLaunchFeatureWall: View {
    let geometry: DocumentLaunchGeometryProxy

    private enum Tile {
        case formula, number, percent, date, boolean
        case columnChart, lineChart, pieChart
        case comment, macro, checkBox, picture
    }

    /// Each row starts at a different tile so no two neighbours repeat. Rows
    /// run wider than the screen and are cut off at its edges, like a wall
    /// that carries on out of frame.
    private let rows: [[Tile]] = [
        [.formula, .number, .columnChart, .comment, .date, .pieChart, .macro],
        [.lineChart, .percent, .checkBox, .formula, .picture, .boolean, .number],
        [.date, .pieChart, .macro, .columnChart, .percent, .comment, .checkBox],
        [.picture, .boolean, .number, .lineChart, .formula, .pieChart, .date],
    ]

    private let tileHeight = 40.0
    private let spacing = 8.0

    var body: some View {
        // Centred in the header, so the wall runs from the top of the launch
        // area to behind the button.
        let headerLine = DocumentLaunch.headerLine(in: geometry)

        VStack(spacing: spacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: spacing) {
                    ForEach(rows[index].indices, id: \.self) { position in
                        tile(rows[index][position])
                    }
                }
                .fixedSize()
                // Alternate rows shift sideways, so the joints stagger like
                // brickwork instead of lining up into columns.
                .offset(x: index.isMultiple(of: 2) ? -24 : 24)
            }
        }
        .frame(width: geometry.frame.width)
        .clipped()
        // Faded as one layer, so overlapping tile edges do not show through.
        .compositingGroup()
        .opacity(0.45)
        .position(
            x: geometry.frame.midX,
            y: headerLine
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(_ tile: Tile) -> some View {
        switch tile {
        case .formula: formulaTile
        case .number: valueTile("1,280.50")
        case .percent: valueTile("12.5%")
        case .date: valueTile("2026-10-07")
        case .boolean: valueTile("TRUE")
        case .columnChart: columnChartTile
        case .lineChart: lineChartTile
        case .pieChart: pieChartTile
        case .comment: symbolTile("text.bubble.fill", color: .orange)
        case .macro: macroTile
        case .checkBox: symbolTile("checkmark.square.fill", color: .blue)
        case .picture: symbolTile("photo.fill", color: .cyan)
        }
    }

    private func tile(width: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, width == nil ? 12 : 0)
            .frame(width: width, height: tileHeight)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    private func symbolTile(_ name: String, color: Color) -> some View {
        tile(width: tileHeight) {
            Image(systemName: name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    /// A cell's value. Numbers, dates and booleans rather than words, so the
    /// wall reads the same in every language.
    private func valueTile(_ value: String) -> some View {
        tile {
            Text(verbatim: value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private var formulaTile: some View {
        tile {
            HStack(spacing: 6) {
                Text(verbatim: "fx")
                    .font(.system(size: 12, weight: .semibold, design: .serif).italic())
                    .foregroundStyle(.secondary)
                Text(verbatim: "=SUM(B2:B9)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var macroTile: some View {
        tile {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.indigo)
                Text(verbatim: "Sub Main()")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
    }

    // The charts use system colours, which already adapt to dark mode, and
    // none of them green so they stand apart from the backdrop.

    private var columnChartTile: some View {
        tile(width: 60) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(zip([0.45, 0.8, 0.6, 1.0], [Color.blue, .orange, .pink, .purple])), id: \.0) { height, color in
                    Capsule()
                        .fill(color)
                        .frame(width: 6, height: 20 * height)
                }
            }
        }
    }

    private var lineChartTile: some View {
        tile(width: 60) {
            Path { path in
                let points = [0.2, 0.55, 0.35, 0.8, 0.6, 1.0]
                for (index, value) in points.enumerated() {
                    let point = CGPoint(x: Double(index) * 7, y: 20 * (1 - value))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .frame(width: 35, height: 20)
        }
    }

    private var pieChartTile: some View {
        tile(width: tileHeight) {
            ZStack {
                ForEach(Array(zip([(0.0, 0.45), (0.45, 0.75), (0.75, 1.0)], [Color.orange, .pink, .purple])), id: \.0.0) { slice, color in
                    Circle()
                        .trim(from: slice.0, to: slice.1)
                        .stroke(color, lineWidth: 10)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 10, height: 10)
        }
    }
}
