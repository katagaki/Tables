import SwiftUI

/// The scrollable spreadsheet canvas.
///
/// The content is laid out absolutely inside one two-axis `ScrollView`, and only
/// the tiles intersecting the viewport are built. Headers live in an overlay
/// that counter-translates with the scroll offset, which keeps them pinned in
/// both axes without nesting scroll views.
///
/// The cells themselves are drawn rather than built: a tile is a single
/// `Canvas`, and everything that moves independently of them — the selection,
/// the in-cell editor, the menu anchor — is a sibling overlay, so none of it
/// reaches the drawing and none of it makes the grid redraw.
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
    /// Where the pinch in progress began. Nil when no pinch is running.
    @State private var zoomAnchor: ZoomAnchor?
    /// The grid point the selection handle started from, in content coordinates.
    /// Non-nil only while the handle is being dragged.
    @State private var handleDragOrigin: CGPoint?
    /// The last cell tapped and when, so a second tap on it can open the menu.
    @State private var lastTap: (address: CellAddress, time: Date)?
    /// Bumped to raise the cell menu from a double tap or a long press.
    @State private var cellMenuTrigger = 0
    @FocusState private var isCellEditorFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
    /// Where the pointer last was, for the right-click menu to read.
    ///
    /// A reference rather than view state on purpose: the pointer moves
    /// continuously, and invalidating the grid on every mouse move to store a
    /// point nothing draws from would undo the work of not rebuilding it.
    @State private var pointer = PointerLocation()

    private final class PointerLocation {
        var location: CGPoint = .zero
    }
    #endif

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
                headerOverlay(in: proxy)
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
                // At least the viewport in both axes. A sheet small enough to
                // fit leaves the scroll view sizing its content to the grid,
                // and a content box smaller than the viewport gets centred —
                // which drags the headers off the top-left corner and floats
                // the whole sheet in the middle of the screen.
                .frame(
                    width: max(proxy.size.width, rowHeaderWidth + metrics.totalWidth + trailingPadding),
                    height: max(proxy.size.height, columnHeaderHeight + metrics.totalHeight + bottomPadding),
                    alignment: .topLeading
                )
        }
            .scrollPosition($scrollPosition)
            .scrollBounceBehavior(.basedOnSize)
            // Canvas, not paper: the sheet paints its own extent, so anything
            // past the last row and column reads as the space around the sheet
            // rather than as grid that failed to draw.
            .background(Color.sheetCanvas)
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
                let anchor = zoomAnchor ?? ZoomAnchor(
                    zoom: state.zoom,
                    scrollOffset: state.scrollOffset,
                    location: value.startLocation,
                    headers: CGSize(width: rowHeaderWidth, height: columnHeaderHeight),
                    viewport: state.viewportSize
                )
                zoomAnchor = anchor
                let target = (anchor.zoom * value.magnification)
                    .clamped(to: EditorState.zoomRange)
                guard abs(target - state.zoom) > 0.001 else { return }
                state.zoom = target
                state.refreshMetrics(in: workbook)
                // The metrics have already grown, so the content box the new
                // offset is clamped against is the one being scrolled.
                let offset = anchor.scrollOffset(at: target, contentSize: CGSize(
                    width: rowHeaderWidth + metrics.totalWidth + trailingPadding,
                    height: columnHeaderHeight + metrics.totalHeight + bottomPadding
                ))
                // Back into the raw offsets `ScrollPosition` works in, and
                // without an animation: the pinch is already the animation.
                scrollPosition.scrollTo(point: CGPoint(
                    x: offset.x - state.scrollInsets.width,
                    y: offset.y - state.scrollInsets.height
                ))
            }
            .onEnded { _ in zoomAnchor = nil }
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
            Rectangle()
                .fill(Color.sheetBackground)
                .frame(width: metrics.totalWidth, height: metrics.totalHeight)

            tiles
            selectionOverlay
            editorOverlay
            cellMenuAnchor
        }
        .padding(.leading, rowHeaderWidth)
        .padding(.top, columnHeaderHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The drawn grid, plus the one tap and one long press that serve all of it.
    ///
    /// Both gestures live here rather than on the cells so that the sheet can be
    /// drawn instead of built. They read the cell out of the touch point, which
    /// the metrics already answer in constant time.
    private var tiles: some View {
        // The sheet and the window are resolved once and handed down. Both are
        // computed properties reaching through the workbook, and a tile asking
        // for them apiece is work repeated on every scroll frame.
        let sheet = activeSheet
        let plans = tilePlans(rows: visibleRows, columns: visibleColumns)
        // Measured against the tiles rather than the viewport, so that what a
        // tile holds depends only on which tile it is. A merge found only once
        // the window had scrolled onto it would leave the tile's cached drawing
        // showing the cells underneath instead of the merge.
        let merges = visibleMerges(in: sheet, coveredBy: plans)

        return ZStack(alignment: .topLeading) {
            ForEach(plans) { plan in
                let frame = metrics.frame(for: plan.range)
                GridTileView(
                    rows: plan.rows,
                    columns: plan.columns,
                    origin: frame.origin,
                    size: frame.size,
                    hiddenRows: sheet.hiddenRows,
                    hiddenColumns: sheet.hiddenColumns,
                    contents: contents(of: plan, in: sheet, merges: merges),
                    metrics: metrics,
                    scheme: colorScheme
                )
                .equatable()
            }
        }
        .frame(width: metrics.totalWidth, height: metrics.totalHeight, alignment: .topLeading)
        .contentShape(.rect)
        .onTapGesture(coordinateSpace: .local) { point in tap(address(at: point)) }
        #if canImport(UIKit)
        // A long press raises the same menu the double tap does. It comes from
        // UIKit rather than from a SwiftUI gesture because only UIKit's
        // recognizer says *where* the press landed, which is the whole question
        // once the cells are drawn instead of built.
        .overlay { LongPressLocator { point in raiseCellMenu(at: point) } }
        #endif
        #if os(macOS)
        .onContinuousHover(coordinateSpace: .local) { phase in
            if case .active(let point) = phase { pointer.location = point }
        }
        .contextMenu { HeaderActionMenu(actions: cellActions(for: address(at: pointer.location))) }
        #endif
    }

    // MARK: - Tiles

    /// One tile's place in the grid.
    private struct TilePlan: Identifiable {
        let id: Int
        let rows: Range<Int>
        let columns: Range<Int>

        var range: CellRange {
            CellRange(
                start: CellAddress(row: rows.lowerBound, column: columns.lowerBound),
                end: CellAddress(row: rows.upperBound - 1, column: columns.upperBound - 1)
            )
        }
    }

    /// Roughly how big a tile should be, before it is rounded to whole lines.
    /// Small enough that a tile scrolling into view is cheap to draw, large
    /// enough that a screenful is a dozen or so of them rather than a hundred.
    private static let tileExtent: Double = 400

    /// The tiles covering a window.
    ///
    /// Bands are cut from the sheet's own line numbering, never from the window:
    /// bands measured from the viewport would shift under every frame and no
    /// tile would ever be reused.
    private func tilePlans(rows: Range<Int>, columns: Range<Int>) -> [TilePlan] {
        guard !rows.isEmpty, !columns.isEmpty else { return [] }
        let rowSpan = tileSpan(extent: metrics.totalHeight, lines: metrics.rowCount)
        let columnSpan = tileSpan(extent: metrics.totalWidth, lines: metrics.columnCount)

        var plans: [TilePlan] = []
        for rowBand in (rows.lowerBound / rowSpan)...((rows.upperBound - 1) / rowSpan) {
            let bandRows = (rowBand * rowSpan)..<min(metrics.rowCount, (rowBand + 1) * rowSpan)
            guard !bandRows.isEmpty else { continue }
            for columnBand in (columns.lowerBound / columnSpan)...((columns.upperBound - 1) / columnSpan) {
                let bandColumns =
                    (columnBand * columnSpan)..<min(metrics.columnCount, (columnBand + 1) * columnSpan)
                guard !bandColumns.isEmpty else { continue }
                plans.append(TilePlan(
                    id: rowBand << 20 | columnBand, rows: bandRows, columns: bandColumns
                ))
            }
        }
        return plans
    }

    /// How many lines make up a band, from the average line size so that zoom
    /// and unusually tall rows both land on a sensible tile.
    private func tileSpan(extent: Double, lines: Int) -> Int {
        guard lines > 0, extent > 0 else { return 16 }
        let average = extent / Double(lines)
        return max(2, min(64, Int((Self.tileExtent / average).rounded())))
    }

    /// Everything inside a tile that has something to draw.
    ///
    /// Blank cells are left out: they need only their separators, which the tile
    /// derives from its line ranges. On a sheet that is mostly empty — which is
    /// most sheets — that is the difference between a handful of entries per
    /// tile and a hundred.
    private func contents(
        of plan: TilePlan, in sheet: Worksheet, merges: [CellRange]
    ) -> TileContents {
        var painted = TileContents()
        var covered: Set<CellAddress> = []

        let window = plan.range
        for merge in merges where merge.intersects(window) {
            let box = merge.normalized
            painted.merges.append(PaintedMerge(
                range: box,
                frame: metrics.frame(for: box),
                cell: sheet[box.start],
                ownsElement: plan.rows.contains(box.start.row)
                    && plan.columns.contains(box.start.column)
            ))
            let firstRow = max(box.start.row, plan.rows.lowerBound)
            let lastRow = min(box.end.row, plan.rows.upperBound - 1)
            let firstColumn = max(box.start.column, plan.columns.lowerBound)
            let lastColumn = min(box.end.column, plan.columns.upperBound - 1)
            guard firstRow <= lastRow, firstColumn <= lastColumn else { continue }
            for row in firstRow...lastRow {
                for column in firstColumn...lastColumn {
                    covered.insert(CellAddress(row: row, column: column))
                }
            }
        }

        for row in plan.rows where !sheet.hiddenRows.contains(row) {
            for column in plan.columns where !sheet.hiddenColumns.contains(column) {
                let address = CellAddress(row: row, column: column)
                guard !covered.contains(address),
                      let cell = sheet.cells[address], !cell.isEmptyEntirely else { continue }
                painted.cells.append(PaintedCell(
                    address: address, frame: metrics.frame(for: address), cell: cell
                ))
            }
        }
        return painted
    }

    /// Merged regions intersecting the tiles being built.
    ///
    /// Merges get a pass of their own rather than being drawn by the cell at
    /// their top-left corner: that corner is frequently outside the tile the
    /// rest of the region falls in, and the region still has to draw. Testing
    /// the whole rectangle against the window — not just its origin — is what
    /// makes that case work.
    private func visibleMerges(in sheet: Worksheet, coveredBy plans: [TilePlan]) -> [CellRange] {
        // The bands run row-major, so the first and last plans are opposite
        // corners of everything they cover between them.
        guard !sheet.mergedRanges.isEmpty,
              let first = plans.first, let last = plans.last else { return [] }
        let window = CellRange(
            start: CellAddress(row: first.rows.lowerBound, column: first.columns.lowerBound),
            end: CellAddress(row: last.rows.upperBound - 1, column: last.columns.upperBound - 1)
        )
        return sheet.mergedRanges.filter { $0.intersects(window) }
    }

    /// The cell under a point in the grid's own coordinates.
    private func address(at point: CGPoint) -> CellAddress {
        let address = CellAddress(
            row: metrics.row(atY: point.y), column: metrics.column(atX: point.x)
        )
        // A tap anywhere in a merge is a tap on the merge.
        return activeSheet.mergedRange(containing: address)?.normalized.start ?? address
    }

    /// A tap either points at a cell for the formula being typed, moves the
    /// selection there, or — when it is the second tap on the same cell —
    /// opens the cell menu, which is the same menu a long press raises.
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
            cellMenuTrigger += 1
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

    // MARK: - Cell menu

    private func cellActions(for address: CellAddress) -> [HeaderMenuAction] {
        CellMenuBuilder(address: address, workbook: $workbook, state: state).actions()
    }

    /// Moves the selection onto the pressed cell, then raises its menu. The
    /// anchor follows the selection, so the order matters.
    private func raiseCellMenu(at point: CGPoint) {
        let address = address(at: point)
        if state.editingAddress != nil { state.commitEditing(in: &workbook, then: nil) }
        state.select(address, in: activeSheet)
        cellMenuTrigger += 1
    }

    /// The menu hangs from here.
    ///
    /// One anchor sitting over the selected cell rather than a presenter inside
    /// every cell: a platform view per cell would be paid for on every scroll
    /// frame. Both the double tap and the long press have already moved the
    /// selection onto the cell they landed on by the time the menu is raised, so
    /// the anchor is always in the right place.
    private var cellMenuAnchor: some View {
        let address = state.selectedAddress
        let frame = metrics.frame(
            for: activeSheet.mergedRange(containing: address) ?? CellRange(address)
        )
        return NativeMenuPresenter(
            actions: { cellActions(for: address) }, trigger: cellMenuTrigger
        )
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
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
        // The fill and border are decoration drawn over the cells: they must
        // let taps through, or a tap inside a selected range would land on the
        // overlay and leave the range standing instead of collapsing it. Only
        // the grip takes touches.
        .allowsHitTesting(false)
        .overlay(alignment: .bottomTrailing) {
            if !isEditing { selectionHandle(from: box, tint: tint) }
        }
        .offset(x: frame.minX, y: frame.minY)
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
            .accessibilityLabel("Grid.ExtendSelection")
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
                // Exactly the cell, padded exactly as the cell paints its text,
                // so opening the editor neither grows the box nor shifts the
                // glyphs. A field too narrow to hold what is being typed scrolls
                // its own contents, which is what a spreadsheet does anyway.
                .padding(.horizontal, 6 * metrics.zoom)
                .frame(width: frame.width, height: frame.height, alignment: .leading)
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

    /// The header strips stop where the sheet does rather than running the full
    /// width and height of the screen: a sheet smaller than the viewport would
    /// otherwise be framed by headers labelling rows and columns that are not
    /// there.
    private func headerOverlay(in proxy: GeometryProxy) -> some View {
        let visibleGridWidth = max(
            0, min(proxy.size.width - rowHeaderWidth, metrics.totalWidth - state.scrollOffset.x)
        )
        let visibleGridHeight = max(
            0, min(proxy.size.height - columnHeaderHeight, metrics.totalHeight - state.scrollOffset.y)
        )

        return ZStack(alignment: .topLeading) {
            columnHeaders
                .frame(width: visibleGridWidth, height: columnHeaderHeight)
                .offset(x: rowHeaderWidth)

            rowHeaders
                .frame(width: rowHeaderWidth, height: visibleGridHeight)
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
                        actions: {
                            HeaderMenuBuilder(
                                axis: .column, index: column, workbook: $workbook, state: state
                            ).actions()
                        }
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
                        actions: {
                            HeaderMenuBuilder(
                                axis: .row, index: row, workbook: $workbook, state: state
                            ).actions()
                        }
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
        .accessibilityLabel("Grid.SelectAll")
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

    /// The surface the paper sits on, past the last row and column.
    static let sheetCanvas: Color = {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color(nsColor: .underPageBackgroundColor)
        #endif
    }()
}

/// A pinch in progress, and the sums that keep the sheet under the fingers.
///
/// Everything here is captured once, when the gesture starts, rather than read
/// live: the gesture writes the scroll offset, so measuring each frame against
/// the current one would feed its own output back into its input and the sheet
/// would crawl away from the fingers over the course of a pinch.
struct ZoomAnchor: Equatable {
    let zoom: Double
    let scrollOffset: CGPoint
    /// The pinch's midpoint, in viewport coordinates.
    let location: CGPoint
    /// The pinned header strips: the row gutter's width and the column
    /// header's height. They do not scale, so they stay out of the sums.
    let headers: CGSize
    let viewport: CGSize

    /// Where to scroll so that whatever was under the fingers when the pinch
    /// began is still under them at `zoom`.
    ///
    /// The grid is measured in points that already have the zoom folded in, so
    /// the content only ever grows away from its top-left corner. Scaling the
    /// distance from that corner to the pinch's midpoint by the same ratio, and
    /// scrolling there, is what turns growth from the corner into growth from
    /// the fingers.
    func scrollOffset(at zoom: Double, contentSize: CGSize) -> CGPoint {
        let scale = zoom / self.zoom
        // The point under the fingers, relative to the grid's own corner.
        let grid = CGPoint(
            x: scrollOffset.x + location.x - headers.width,
            y: scrollOffset.y + location.y - headers.height
        )
        // A sheet smaller than the viewport still fills it, and cannot scroll.
        let scrollableWidth = max(0, max(viewport.width, contentSize.width) - viewport.width)
        let scrollableHeight = max(0, max(viewport.height, contentSize.height) - viewport.height)
        return CGPoint(
            x: (grid.x * scale + headers.width - location.x).clamped(to: 0...scrollableWidth),
            y: (grid.y * scale + headers.height - location.y).clamped(to: 0...scrollableHeight)
        )
    }
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
