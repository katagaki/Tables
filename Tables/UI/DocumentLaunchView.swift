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
/// formulas, charts, tables, conditional formats, comments, macros, form
/// controls and pictures — laid in staggered rows across the whole header. It sits behind
/// the buttons, faded so it reads as a backdrop rather than content.
/// Decoration only, so hidden from VoiceOver.
struct DocumentLaunchFeatureWall: View {
    let geometry: DocumentLaunchGeometryProxy

    private enum Tile {
        case value(String), formula(String), macro(String)
        case columnChart, barChart, lineChart, areaChart, pieChart, doughnutChart, scatterChart
        case table, dataBar, colorScale
        case comment, note, checkBox, optionButton, dropDown, picture
    }

    /// No tile appears twice in a row, and the kinds are spread so neighbours
    /// differ. Rows start just off the leading edge and run past the trailing
    /// one, like a wall that carries on out of frame, so the most telling
    /// tiles come first, where a phone shows them. The rows shifted furthest
    /// open on a small icon tile, which loses little to the edge.
    private let rows: [[Tile]] = [
        [.formula("=SUM(B2:B9)"), .columnChart, .value("1,280.50"), .comment,
         .doughnutChart, .value("2026-10-07"), .macro("Sub Main()"), .dataBar],
        [.checkBox, .table, .value("12.5%"), .scatterChart,
         .formula("=AVERAGE(C2:C31)"), .picture, .value("TRUE"), .lineChart],
        [.value("09:30"), .areaChart, .dropDown, .colorScale,
         .formula("=TODAY()"), .pieChart, .value("-42.00"), .optionButton],
        [.note, .barChart, .value("#N/A"), .macro("End Sub"),
         .formula("=VLOOKUP(A2,Data!A:C,3)"), .value("3.14159"), .columnChart, .optionButton],
    ]

    private let tileHeight = 40.0
    private let spacing = 8.0

    var body: some View {
        // Centred in the header, so the wall runs from the top of the launch
        // area to behind the button.
        let headerLine = DocumentLaunch.headerLine(in: geometry)

        VStack(alignment: .leading, spacing: spacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: spacing) {
                    ForEach(rows[index].indices, id: \.self) { position in
                        tile(rows[index][position])
                    }
                }
                .fixedSize()
                // Alternate rows shift sideways, so the joints stagger like
                // brickwork instead of lining up into columns.
                .offset(x: index.isMultiple(of: 2) ? -16 : -44)
            }
        }
        .frame(width: geometry.frame.width, alignment: .leading)
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
        case .value(let value): valueTile(value)
        case .formula(let formula): formulaTile(formula)
        case .macro(let line): macroTile(line)
        case .columnChart: columnChartTile
        case .barChart: barChartTile
        case .lineChart: lineChartTile
        case .areaChart: areaChartTile
        case .pieChart: pieChartTile(lineWidth: 10, diameter: 10)
        case .doughnutChart: pieChartTile(lineWidth: 5, diameter: 15)
        case .scatterChart: scatterChartTile
        case .table: tableTile
        case .dataBar: dataBarTile
        case .colorScale: colorScaleTile
        case .comment: symbolTile("text.bubble.fill", color: .orange)
        case .note: symbolTile("note.text", color: .yellow)
        case .checkBox: symbolTile("checkmark.square.fill", color: .blue)
        case .optionButton: symbolTile("largecircle.fill.circle", color: .blue)
        case .dropDown: dropDownTile
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

    private func formulaTile(_ formula: String) -> some View {
        tile {
            HStack(spacing: 6) {
                Text(verbatim: "fx")
                    .font(.system(size: 12, weight: .semibold, design: .serif).italic())
                    .foregroundStyle(.secondary)
                Text(verbatim: formula)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func macroTile(_ line: String) -> some View {
        tile {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.indigo)
                Text(verbatim: line)
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

    private func pieChartTile(lineWidth: Double, diameter: Double) -> some View {
        tile(width: tileHeight) {
            ZStack {
                ForEach(Array(zip([(0.0, 0.45), (0.45, 0.75), (0.75, 1.0)], [Color.orange, .pink, .purple])), id: \.0.0) { slice, color in
                    Circle()
                        .trim(from: slice.0, to: slice.1)
                        .stroke(color, lineWidth: lineWidth)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: diameter, height: diameter)
        }
    }

    private var barChartTile: some View {
        tile(width: 60) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(zip([0.6, 1.0, 0.4, 0.75], [Color.blue, .orange, .pink, .purple])), id: \.0) { length, color in
                    Capsule()
                        .fill(color)
                        .frame(width: 34 * length, height: 4)
                }
            }
            .frame(width: 34, alignment: .leading)
        }
    }

    private var areaChartTile: some View {
        tile(width: 60) {
            let values = [0.3, 0.5, 0.4, 0.75, 0.6, 0.9]
            let step = 7.0
            let curve = Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: Double(index) * step, y: 20 * (1 - value))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            ZStack {
                Path { path in
                    path.addPath(curve)
                    path.addLine(to: CGPoint(x: Double(values.count - 1) * step, y: 20))
                    path.addLine(to: CGPoint(x: 0, y: 20))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [.purple.opacity(0.5), .purple.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                curve.stroke(.purple, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 35, height: 20)
        }
    }

    private var scatterChartTile: some View {
        tile(width: 60) {
            let points: [(Double, Double, Color)] = [
                (0.05, 0.8, .blue), (0.25, 0.55, .orange), (0.4, 0.7, .blue), (0.55, 0.3, .pink),
                (0.7, 0.45, .orange), (0.85, 0.15, .blue), (0.95, 0.35, .pink),
            ]
            ZStack(alignment: .topLeading) {
                ForEach(points.indices, id: \.self) { index in
                    Circle()
                        .fill(points[index].2)
                        .frame(width: 5, height: 5)
                        .offset(x: 34 * points[index].0 - 2.5, y: 22 * points[index].1 - 2.5)
                }
            }
            .frame(width: 34, height: 22, alignment: .topLeading)
        }
    }

    /// A formatted table: a coloured header row over banded rows.
    private var tableTile: some View {
        tile(width: 60) {
            VStack(spacing: 1.5) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 1.5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(row == 0 ? Color.blue : Color.blue.opacity(row.isMultiple(of: 2) ? 0.3 : 0.12))
                                .frame(width: 11, height: 5)
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 2))
        }
    }

    /// A cell with a conditional-format data bar running behind its value.
    private var dataBarTile: some View {
        tile {
            Text(verbatim: "842")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 56, alignment: .trailing)
                .padding(.trailing, 4)
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [.blue.opacity(0.6), .blue.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 42, height: 20)
                }
        }
    }

    /// A row of cells shaded by a conditional-format colour scale.
    private var colorScaleTile: some View {
        tile {
            HStack(spacing: 2) {
                ForEach([Color.red, .orange, .yellow, .mint], id: \.self) { color in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.75))
                        .frame(width: 14, height: 20)
                }
            }
        }
    }

    private var dropDownTile: some View {
        tile {
            HStack(spacing: 8) {
                Text(verbatim: "Q4")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
