import SwiftUI

/// The pieces of the document picker's top area: a green field ruled like a
/// sheet, with a few cells of work set beside the title.
enum DocumentLaunch {
    /// A wash of the app icon's green, kept quiet: near white in light mode,
    /// near black in dark, so the system's black or white title reads over it
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

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// The green wash, ruled with faint gridlines that fade out towards the
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

/// A wall of small tiles, one per thing Tables does — formulas, charts,
/// comments, macros, formatting, sorting and filtering, drawing and Shortcuts —
/// set flat in the empty space beside the leading-aligned title. Decoration
/// only, so hidden from VoiceOver.
struct DocumentLaunchOverlay: View {
    let geometry: DocumentLaunchGeometryProxy

    private let tileHeight = 40.0
    private let spacing = 8.0

    var body: some View {
        // The title frame spans the title and the actions beneath it; the
        // title's own line sits about 90pt below its top. The wall's last row
        // shares that line, beside the title, and the rows above it stack up
        // towards the top of the launch area.
        let titleLine = geometry.titleViewFrame.minY + 90
        let width = geometry.frame.width - 48

        VStack(alignment: .trailing, spacing: spacing) {
            HStack(spacing: spacing) {
                formulaTile
                symbolTile("text.bubble.fill", color: .orange)
                formattingTile
            }
            HStack(spacing: spacing) {
                referenceTile
                chartTile
                macroTile
                symbolTile("pencil.tip", color: .pink)
            }
            HStack(spacing: spacing) {
                symbolTile("arrow.up.arrow.down", color: .blue)
                symbolTile("line.3.horizontal.decrease", color: .teal)
                swatchTile
            }
        }
        .frame(width: width, alignment: .trailing)
        .position(
            x: geometry.frame.midX,
            y: titleLine - (tileHeight + spacing)
        )
        .accessibilityHidden(true)
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

    private var referenceTile: some View {
        tile(width: 44) {
            Text(verbatim: "A1")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private var formattingTile: some View {
        tile {
            HStack(spacing: 10) {
                Text(verbatim: "B").bold()
                Text(verbatim: "I").italic()
                Text(verbatim: "U").underline()
            }
            .font(.system(size: 15, design: .serif))
            .foregroundStyle(.primary)
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

    private var chartTile: some View {
        tile(width: 60) {
            HStack(alignment: .bottom, spacing: 4) {
                // System colours, which already adapt to dark mode, and none of
                // them green so the bars stand apart from the backdrop.
                ForEach(Array(zip([0.45, 0.8, 0.6, 1.0], [Color.blue, .orange, .pink, .purple])), id: \.0) { height, color in
                    Capsule()
                        .fill(color)
                        .frame(width: 6, height: 20 * height)
                }
            }
        }
    }

    private var swatchTile: some View {
        tile {
            HStack(spacing: -4) {
                ForEach([Color.red, .yellow, .cyan], id: \.self) { color in
                    Circle()
                        .fill(color)
                        .stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2)
                        .frame(width: 18, height: 18)
                }
            }
        }
    }
}
