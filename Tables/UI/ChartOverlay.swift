import SwiftUI

/// One chart floating over the grid.
///
/// A tap picks it out; once picked out, dragging it moves it, the corner grip
/// resizes it, and a further tap opens the chart panel. While it is not
/// selected a drag over it scrolls the sheet like anywhere else — a chart that
/// swallowed every pan would make a sheet full of them impossible to move
/// around in.
struct EmbeddedChartView: View {
    let chart: Chart
    let data: ResolvedChart
    /// Where the chart sits, in the grid's own zoomed coordinates.
    let frame: CGRect
    let zoom: Double
    let isSelected: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    /// The new frame, in the grid's zoomed coordinates.
    var onCommit: (CGRect) -> Void
    var onMoveToNewSheet: () -> Void
    var onDelete: () -> Void

    @State private var translation: CGSize = .zero
    @State private var growth: CGSize = .zero

    private let gripDiameter: Double = 18

    var body: some View {
        let width = max(48, frame.width + growth.width)
        let height = max(36, frame.height + growth.height)

        ChartView(chart: chart, data: data, zoom: zoom)
            .equatable()
            .frame(width: width, height: height)
            // Here rather than on the whole view, so the grip keeps its own.
            .accessibilityIdentifier("chart.\(chart.name)")
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08), radius: isSelected ? 8 : 3, y: 1)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(-1)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect)
            .gesture(interaction)
            .overlay(alignment: .bottomTrailing) {
                if isSelected { resizeGrip }
            }
            .contextMenu {
                Button("Chart.Menu.Edit", systemImage: "slider.horizontal.3") {
                    onSelect()
                    onEdit()
                }
                Button("Chart.Menu.MoveToNewSheet", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                    onSelect()
                    onMoveToNewSheet()
                }
                Divider()
                Button("Chart.Menu.Delete", systemImage: "trash", role: .destructive) {
                    onSelect()
                    onDelete()
                }
            }
            .offset(x: frame.minX + translation.width, y: frame.minY + translation.height)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(named: Text("Chart.Menu.Edit")) {
                onSelect()
                onEdit()
            }
    }

    /// Unselected, a plain tap: anything more is the scroll view's. Selected,
    /// a drag from a standing start, so the chart follows the finger from its
    /// first point — and a drag that never went anywhere was a tap.
    private var interaction: AnyGesture<Void> {
        if isSelected {
            return AnyGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { translation = $0.translation }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        if distance > 4 {
                            onCommit(frame.offsetBy(dx: value.translation.width, dy: value.translation.height))
                        } else {
                            onEdit()
                        }
                        translation = .zero
                    }
                    .map { _ in () }
            )
        }
        return AnyGesture(TapGesture().onEnded { onSelect() })
    }

    private var resizeGrip: some View {
        Color.clear
            .frame(width: gripDiameter, height: gripDiameter)
            .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
            .background { Circle().fill(Color.sheetBackground).padding(-2) }
            .offset(x: gripDiameter / 2, y: gripDiameter / 2)
            .contentShape(.rect.inset(by: -16))
            .gesture(
                // Global space, for the same reason as the selection grip: the
                // grip rides the edge it is dragging.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { growth = $0.translation }
                    .onEnded { value in
                        var resized = frame
                        resized.size.width = max(48, frame.width + value.translation.width)
                        resized.size.height = max(36, frame.height + value.translation.height)
                        onCommit(resized)
                        growth = .zero
                    }
            )
            .accessibilityIdentifier("chartResizeGrip")
            .accessibilityLabel("Chart.Resize")
    }
}

/// A chart sheet: the chart, filling the space the grid would.
struct ChartSheetView: View {
    @Binding var workbook: Workbook
    @Bindable var state: EditorState
    let sheet: Worksheet

    var body: some View {
        Group {
            if let chart = sheet.charts.first {
                ChartView(chart: chart, data: chart.resolved(in: workbook))
                    .equatable()
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                    .contentShape(.rect)
                    .onTapGesture {
                        state.selectChart(chart.id)
                        state.presentedPanel = .chart
                    }
                    .contextMenu {
                        Button("Chart.Menu.Edit", systemImage: "slider.horizontal.3") {
                            state.selectChart(chart.id)
                            state.presentedPanel = .chart
                        }
                        Divider()
                        Button("Chart.Menu.Delete", systemImage: "trash", role: .destructive) {
                            state.deleteSelectedChart(in: &workbook)
                        }
                    }
                    .accessibilityIdentifier("chartSheet.chart")
            } else if let anchor = sheet.preservedDrawingAnchors.first {
                PreservedDrawingPlaceholder(isChart: anchor.isChart, zoom: 1.5)
            } else {
                ContentUnavailableView("Chart.Empty", systemImage: "chart.bar.xaxis")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sheetCanvas)
    }
}
