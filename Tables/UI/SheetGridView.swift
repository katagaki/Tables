import SwiftUI

/// The scrollable spreadsheet canvas.
///
/// The content is laid out absolutely inside one two-axis `ScrollView`, and only
/// the cells intersecting the viewport are built. Headers live in an overlay
/// that counter-translates with the scroll offset, which keeps them pinned in
/// both axes without nesting scroll views.
///
/// Nothing about the selection reaches the cell views — it is drawn as a single
/// overlay — so moving between cells never rebuilds the grid.
struct SheetGridView: View {
    @Binding var workbook: Workbook
    @Bindable var state: EditorState

    /// Room past the last row and column so the final cells can scroll clear of
    /// the floating controls.
    private let trailingPadding: Double = 120
    private let bottomPadding: Double = 160
    private let columnHeaderHeight: Double = 28
    private let selectionHandleDiameter: Double = 18

    @State private var scrollPosition = ScrollPosition()
    @State private var zoomAtGestureStart: Double?
    /// The grid point the selection handle started from, in content coordinates.
    /// Non-nil only while the handle is being dragged.
    @State private var handleDragOrigin: CGPoint?
    /// The last cell tapped and when, so a second tap on it can open the editor.
    @State private var lastTap: (address: CellAddress, time: Date)?
    @FocusState private var isCellEditorFocused: Bool

    /// Matches the platform's own double-tap window closely enough that a
    /// deliberate double tap always lands and a slow retap never does.
    private static let doubleTapInterval: TimeInterval = 0.4

    private var activeSheet: Worksheet { state.activeSheet(in: workbook) }
    private var metrics: SheetMetrics { state.metrics }

    private var rowHeaderWidth: Double {
        // Widen the gutter as row numbers get longer.
        44 + Double(max(0, String(activeSheet.rowCount).count - 3)) * 9
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                grid(in: proxy)
                // A sibling rather than an overlay: the scroll view draws under
                // the navigation bar, and the pinned headers must not follow it
                // up into the safe area.
                headerOverlay
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipped()
            }
        }
        .onChange(of: activeSheet.id) { _, _ in state.refreshMetrics(in: workbook) }
        .onChange(of: activeSheet.rowCount) { _, _ in state.refreshMetrics(in: workbook) }
        .onChange(of: activeSheet.columnCount) { _, _ in state.refreshMetrics(in: workbook) }
        .onChange(of: activeSheet.hiddenRows) { _, _ in state.refreshMetrics(in: workbook) }
        .onChange(of: activeSheet.hiddenColumns) { _, _ in state.refreshMetrics(in: workbook) }
        .onChange(of: activeSheet.columnWidths) { _, _ in state.refreshMetrics(in: workbook) }
        .onChange(of: activeSheet.rowHeights) { _, _ in state.refreshMetrics(in: workbook) }
        .onChange(of: state.scrollTarget) { _, target in
            guard let target else { return }
            scrollIntoView(target)
            state.scrollTarget = nil
        }
        .onChange(of: state.editingAddress) { _, address in
            isCellEditorFocused = address != nil && !state.isFormulaBarActive
        }
    }

    private func grid(in proxy: GeometryProxy) -> some View {
        ScrollView([.horizontal, .vertical]) {
            content
                .frame(
                    width: rowHeaderWidth + metrics.totalWidth + trailingPadding,
                    height: columnHeaderHeight + metrics.totalHeight + bottomPadding,
                    alignment: .topLeading
                )
        }
            .scrollPosition($scrollPosition)
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.sheetBackground)
            // `contentOffset` is measured from the scroll view's origin, which
            // sits above the navigation bar's content inset — so it is already
            // negative at rest. Adding the insets back gives distance scrolled
            // from the top-left of the content, which is what the pinned headers
            // and the visible-window maths both want.
            .onScrollGeometryChange(for: ScrollAnchor.self) { geometry in
                ScrollAnchor(
                    offset: CGPoint(
                        x: geometry.contentOffset.x + geometry.contentInsets.leading,
                        y: geometry.contentOffset.y + geometry.contentInsets.top
                    ),
                    insets: CGSize(
                        width: geometry.contentInsets.leading,
                        height: geometry.contentInsets.top
                    )
                )
            } action: { _, anchor in
                state.scrollOffset = anchor.offset
                state.scrollInsets = anchor.insets
            }
            .simultaneousGesture(zoomGesture)
            .onAppear {
                state.viewportSize = proxy.size
                state.refreshMetrics(in: workbook)
            }
            .onChange(of: proxy.size) { _, size in state.viewportSize = size }
    }

    // MARK: - Zoom

    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let base = zoomAtGestureStart ?? state.zoom
                zoomAtGestureStart = base
                let target = (base * value.magnification)
                    .clamped(to: EditorState.zoomRange)
                guard abs(target - state.zoom) > 0.001 else { return }
                state.zoom = target
                state.refreshMetrics(in: workbook)
            }
            .onEnded { _ in zoomAtGestureStart = nil }
    }

    // MARK: - Visible window

    private var visibleRows: Range<Int> {
        let top = state.scrollOffset.y - columnHeaderHeight
        let height = max(state.viewportSize.height, 200)
        return metrics.rows(in: max(0, top)...(top + height))
    }

    private var visibleColumns: Range<Int> {
        let left = state.scrollOffset.x - rowHeaderWidth
        let width = max(state.viewportSize.width, 200)
        return metrics.columns(in: max(0, left)...(left + width))
    }

    // MARK: - Content

    private var content: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleRows, id: \.self) { row in
                if !activeSheet.hiddenRows.contains(row) {
                    ForEach(visibleColumns, id: \.self) { column in
                        if !activeSheet.hiddenColumns.contains(column),
                           activeSheet.mergedRange(containing: CellAddress(row: row, column: column)) == nil {
                            cell(row: row, column: column)
                        }
                    }
                }
            }
            ForEach(visibleMerges, id: \.self) { merge in
                mergedCell(merge)
            }
            selectionOverlay
            editorOverlay
        }
        .padding(.leading, rowHeaderWidth)
        .padding(.top, columnHeaderHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func cell(row: Int, column: Int) -> some View {
        let address = CellAddress(row: row, column: column)
        let frame = metrics.frame(for: address)
        return GridCellView(cell: activeSheet[address], zoom: metrics.zoom)
            .equatable()
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .onTapGesture { tap(address) }
            // One leaf element per cell, so VoiceOver reads "B4, 2180.5" as a unit
            // instead of losing the cell inside the scroll view's contents.
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("cell.\(address.a1)")
            .accessibilityLabel(accessibilityDescription(of: address))
            .accessibilityAddTraits(.isButton)
            .accessibilityRespondsToUserInteraction(true)
    }

    /// Merged regions intersecting the viewport.
    ///
    /// Merges get a pass of their own rather than being drawn by the cell at
    /// their top-left corner: that corner is frequently scrolled outside the
    /// built window while the rest of the region is on screen, and the region
    /// still has to draw. Testing the whole rectangle against the window — not
    /// just its origin — is what makes that case work.
    private var visibleMerges: [CellRange] {
        guard !activeSheet.mergedRanges.isEmpty else { return [] }
        let rows = visibleRows
        let columns = visibleColumns
        guard !rows.isEmpty, !columns.isEmpty else { return [] }
        let window = CellRange(
            start: CellAddress(row: rows.lowerBound, column: columns.lowerBound),
            end: CellAddress(row: rows.upperBound - 1, column: columns.upperBound - 1)
        )
        return activeSheet.mergedRanges.filter { $0.intersects(window) }
    }

    /// One merged region: the top-left cell's content and style, drawn across
    /// the whole range.
    private func mergedCell(_ range: CellRange) -> some View {
        let box = range.normalized
        let frame = metrics.frame(for: box)
        return GridCellView(cell: activeSheet[box.start], zoom: metrics.zoom)
            .equatable()
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .onTapGesture { tap(box.start) }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("cell.\(box.start.a1)")
            .accessibilityLabel(accessibilityDescription(of: box.start))
            .accessibilityAddTraits(.isButton)
            .accessibilityRespondsToUserInteraction(true)
    }

    /// "B4, 2180.5" — the reference followed by whatever the cell shows.
    private func accessibilityDescription(of address: CellAddress) -> String {
        let text = CellFormatter.displayText(for: activeSheet[address])
        return text.isEmpty ? "\(address.a1), empty" : "\(address.a1), \(text)"
    }

    /// A tap either points at a cell for the formula being typed, moves the
    /// selection there, or — when it is the second tap on the same cell —
    /// opens the editor.
    ///
    /// The double tap is timed here rather than handed to a second
    /// `onTapGesture(count: 2)`, because SwiftUI makes the two counts mutually
    /// exclusive: every single tap is then held for the whole double-tap window
    /// before it is delivered, which is a visible pause on every move between
    /// cells. One immediate gesture and a stopwatch gives the same two
    /// behaviours with the selection landing on touch-up.
    private func tap(_ address: CellAddress) {
        if state.isEnteringFormula {
            state.insertReference(CellRange(address), in: workbook)
            return
        }
        if let last = lastTap, last.address == address,
           Date.now.timeIntervalSince(last.time) < Self.doubleTapInterval {
            lastTap = nil
            state.beginEditing(address, in: workbook)
            return
        }
        lastTap = (address, .now)
        if state.editingAddress != nil { state.commitEditing(in: &workbook, then: nil) }
        #if os(macOS)
        state.select(address, extending: NSEvent.modifierFlags.contains(.shift), in: activeSheet)
        #else
        state.select(address, in: activeSheet)
        #endif
    }

    // MARK: - Selection

    /// The selection, its fill and its drag handle — one overlay for the whole
    /// range rather than state threaded through every cell.
    private var selectionOverlay: some View {
        let box = state.isEnteringFormula
            ? (state.pendingReferenceRange ?? state.selection).normalized
            : state.selection.normalized
        let frame = metrics.frame(for: box)
        let isEditing = state.editingAddress != nil && !state.isEnteringFormula
        let tint: Color = state.isEnteringFormula ? .purple : .accentColor

        return ZStack(alignment: .topLeading) {
            // Fill everything but the anchor cell, the way a spreadsheet does.
            Path { path in
                path.addRect(CGRect(origin: .zero, size: frame.size))
                // The anchor is a whole merged region when it lands in one, so
                // the unfilled hole matches what the user sees as one cell.
                let anchor = metrics.frame(
                    for: activeSheet.mergedRange(containing: state.selectedAddress)
                        ?? CellRange(state.selectedAddress)
                )
                if box.contains(state.selectedAddress), !state.isEnteringFormula {
                    path.addRect(anchor.offsetBy(dx: -frame.minX, dy: -frame.minY))
                }
            }
            .fill(tint.opacity(0.14), style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(tint, lineWidth: isEditing ? 2.5 : 2)
        }
        .frame(width: max(frame.width, 1), height: max(frame.height, 1))
        .overlay(alignment: .bottomTrailing) {
            if !isEditing { selectionHandle(from: box, tint: tint) }
        }
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(!isEditing)
        // Settling into a new range looks good for keyboard and tap selection,
        // but an in-flight drag already tracks the finger — animating it there
        // just lags the grip.
        .animation(handleDragOrigin == nil ? .interactiveSpring(duration: 0.16) : nil, value: box)
    }

    /// Numbers-style corner grip: drag it to grow the selection — or, while a
    /// formula is being typed, to grow the reference being pointed at.
    private func selectionHandle(from box: CellRange, tint: Color) -> some View {
        Color.clear
            .frame(width: selectionHandleDiameter, height: selectionHandleDiameter)
            .glassEffect(.regular.tint(tint).interactive(), in: .circle)
            // A halo in the paper colour keeps the grip legible wherever it
            // lands on dense cell content, in either appearance.
            .background { Circle().fill(Color.sheetBackground).padding(-2) }
            .offset(x: selectionHandleDiameter / 2, y: selectionHandleDiameter / 2)
            .contentShape(.rect.inset(by: -16))
            .gesture(
                // Global space and a translation — never `value.location` in a
                // local space — because the grip rides the selection this
                // gesture is resizing. A moving reference frame would feed the
                // drag back into itself and make the range stutter.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let origin = handleDragOrigin ?? cornerPoint(of: box)
                        handleDragOrigin = origin
                        let point = CGPoint(
                            x: origin.x + value.translation.width,
                            y: origin.y + value.translation.height
                        )
                        let target = CellAddress(
                            row: metrics.row(atY: point.y), column: metrics.column(atX: point.x)
                        )
                        if state.isEnteringFormula {
                            let start = state.pendingReferenceRange?.normalized.start ?? target
                            state.insertReference(
                                CellRange(start: start, end: target), in: workbook
                            )
                        } else {
                            state.select(target, extending: true, in: activeSheet)
                        }
                    }
                    .onEnded { _ in handleDragOrigin = nil }
            )
            .accessibilityIdentifier("selectionGrip")
            .accessibilityLabel("Extend selection")
            .accessibilityAddTraits(.isButton)
    }

    /// A point just inside the bottom-right cell of a range — where the grip
    /// sits, and so where a drag from it starts measuring.
    private func cornerPoint(of box: CellRange) -> CGPoint {
        let frame = metrics.frame(for: box)
        return CGPoint(x: frame.maxX - 1, y: frame.maxY - 1)
    }

    // MARK: - In-cell editor

    @ViewBuilder
    private var editorOverlay: some View {
        // While the formula bar has the caret, it owns the edit — showing a
        // second field here would fight it for keyboard focus.
        if let address = state.editingAddress, !state.isFormulaBarActive {
            let frame = metrics.frame(
                for: activeSheet.mergedRange(containing: address) ?? CellRange(address)
            )
            // Single-line on purpose: a vertical-axis field treats Return as a
            // newline instead of committing the cell.
            TextField("", text: $state.editingText)
                .accessibilityIdentifier("cellEditor")
                .textFieldStyle(.plain)
                .font(state.editingText.hasPrefix("=")
                      ? .system(size: 14 * metrics.zoom, design: .monospaced)
                      : activeSheet[address].style.font(zoom: metrics.zoom))
                .padding(.horizontal, 5)
                .frame(width: max(frame.width, 140), height: frame.height, alignment: .leading)
                .background(Color.sheetBackground)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: 2.5))
                .focused($isCellEditorFocused)
                .submitLabel(.done)
                .onSubmit { state.commitEditing(in: &workbook, keepingEditor: true) }
                .onEscapeKey { state.cancelEditing() }
                .offset(x: frame.minX, y: frame.minY)
                .zIndex(2)
        }
    }

    // MARK: - Headers

    private var headerOverlay: some View {
        ZStack(alignment: .topLeading) {
            columnHeaders
                .frame(height: columnHeaderHeight)
                .offset(x: rowHeaderWidth)

            rowHeaders
                .frame(width: rowHeaderWidth)
                .offset(y: columnHeaderHeight)

            cornerButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var columnHeaders: some View {
        ZStack(alignment: .topLeading) {
            Color.headerBackground.background(.regularMaterial)
            ForEach(visibleColumns, id: \.self) { column in
                if !activeSheet.hiddenColumns.contains(column) {
                    ColumnHeaderCell(
                        title: CellAddress.columnName(column),
                        width: metrics.width(ofColumn: column),
                        height: columnHeaderHeight,
                        isSelected: state.selection.normalized.columnRange.contains(column),
                        isHiddenNeighbor: activeSheet.hiddenColumns.contains(column + 1),
                        onSelect: { state.selectEntireColumns(column...column, in: activeSheet) },
                        onResize: { delta in
                            state.resizeColumn(
                                column,
                                to: (metrics.width(ofColumn: column) + delta) / metrics.zoom,
                                in: &workbook
                            )
                        },
                        onFit: { state.fitColumn(column, in: &workbook) },
                        actions: HeaderMenuBuilder(
                            axis: .column, index: column, workbook: $workbook, state: state
                        ).actions()
                    )
                    .offset(x: metrics.x(ofColumn: column) - state.scrollOffset.x)
                }
            }
        }
        .clipped()
    }

    private var rowHeaders: some View {
        ZStack(alignment: .topLeading) {
            Color.headerBackground.background(.regularMaterial)
            ForEach(visibleRows, id: \.self) { row in
                if !activeSheet.hiddenRows.contains(row) {
                    RowHeaderCell(
                        title: String(row + 1),
                        width: rowHeaderWidth,
                        height: metrics.height(ofRow: row),
                        isSelected: state.selection.normalized.rowRange.contains(row),
                        isHiddenNeighbor: activeSheet.hiddenRows.contains(row + 1),
                        onSelect: { state.selectEntireRows(row...row, in: activeSheet) },
                        onResize: { delta in
                            state.resizeRow(
                                row,
                                to: (metrics.height(ofRow: row) + delta) / metrics.zoom,
                                in: &workbook
                            )
                        },
                        actions: HeaderMenuBuilder(
                            axis: .row, index: row, workbook: $workbook, state: state
                        ).actions()
                    )
                    .offset(y: metrics.y(ofRow: row) - state.scrollOffset.y)
                }
            }
        }
        .clipped()
    }

    private var cornerButton: some View {
        Button {
            state.selectAll(in: activeSheet)
        } label: {
            ZStack {
                Color.headerBackground.background(.regularMaterial)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: rowHeaderWidth, height: columnHeaderHeight)
            .overlay(alignment: .trailing) { Rectangle().fill(Color.gridLine).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.gridLine).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select all cells")
    }

    // MARK: - Scrolling

    /// Nudges the scroll offset just enough to reveal a cell under the headers.
    private func scrollIntoView(_ address: CellAddress) {
        let frame = metrics.frame(for: address)
        let visibleWidth = max(1, state.viewportSize.width - rowHeaderWidth)
        let visibleHeight = max(1, state.viewportSize.height - columnHeaderHeight)
        var offset = state.scrollOffset

        if frame.minX < offset.x {
            offset.x = frame.minX
        } else if frame.maxX > offset.x + visibleWidth {
            offset.x = frame.maxX - visibleWidth
        }
        if frame.minY < offset.y {
            offset.y = frame.minY
        } else if frame.maxY > offset.y + visibleHeight {
            offset.y = frame.maxY - visibleHeight
        }
        guard offset != state.scrollOffset else { return }
        // Convert back to the raw content offset the scroll view works in.
        let destination = CGPoint(
            x: max(0, offset.x) - state.scrollInsets.width,
            y: max(0, offset.y) - state.scrollInsets.height
        )
        withAnimation(.easeOut(duration: 0.18)) {
            scrollPosition.scrollTo(point: destination)
        }
    }
}

extension Color {
    /// The paper behind the grid.
    static let sheetBackground: Color = {
        #if canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color(nsColor: .textBackgroundColor)
        #endif
    }()
}

/// Scroll position plus the insets it was measured against, captured together
/// so they can never disagree.
private struct ScrollAnchor: Equatable {
    var offset: CGPoint
    var insets: CGSize
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
