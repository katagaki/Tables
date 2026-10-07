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

/// A formula, a reference and a small chart set flat in the empty space
/// beside the leading-aligned title.
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
        let width = 200.0

        VStack(alignment: .trailing, spacing: 10) {
            formulaChip
            HStack(alignment: .bottom, spacing: 10) {
                referenceChip
                chartChip
            }
        }
        .frame(width: width, alignment: .trailing)
        .position(x: geometry.frame.maxX - 24 - width / 2, y: (bandTop + bandBottom) / 2)
        .accessibilityHidden(true)
    }

    private var formulaChip: some View {
        HStack(spacing: 6) {
            Text(verbatim: "fx")
                .font(.system(size: 12, weight: .semibold, design: .serif).italic())
                .foregroundStyle(.secondary)
            Text(verbatim: "=SUM(B2:B9)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
    }

    private var referenceChip: some View {
        Text(verbatim: "A1")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 32)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
    }

    private var chartChip: some View {
        HStack(alignment: .bottom, spacing: 4) {
            // System colours, which already adapt to dark mode, and none of
            // them green so the bars stand apart from everything around them.
            ForEach(Array(zip([0.45, 0.8, 0.6, 1.0], [Color.blue, .orange, .pink, .purple])), id: \.0) { height, color in
                Capsule()
                    .fill(color)
                    .frame(width: 6, height: 22 * height)
            }
        }
        .frame(width: 60, height: 46)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}
