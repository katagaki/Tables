import Foundation

/// A chart, modelled on the part of DrawingML charts that Excel's own chart
/// gallery produces: one plot of one type, a category axis and a value axis,
/// a title, a legend, and series drawn from ranges of cells.
///
/// Anything richer — combination charts, secondary axes, 3-D, trendlines — is
/// not modelled at all. The reader leaves those charts as preserved drawing
/// anchors instead, so a file is never saved with a chart that has been
/// quietly simplified.
struct Chart: Identifiable, Hashable, Sendable {
    var id = UUID()
    /// What Excel's selection pane calls the chart: "Chart 1".
    var name: String
    var kind: ChartKind
    var grouping: ChartGrouping = .standard
    var series: [ChartSeries] = []

    /// An explicit title. `nil` leaves the choice to `showsAutomaticTitle`.
    var title: ChartTitle?
    /// Excel titles a single-series chart with the series name unless told
    /// not to (`autoTitleDeleted`), so the absence of a title is not the same
    /// thing as no title.
    var showsAutomaticTitle = false

    /// The horizontal axis of a column, line or area chart, the vertical one
    /// of a bar chart, and the X axis of a scatter chart.
    var categoryAxis = ChartAxis()
    /// The axis the values are measured along — the Y axis of a scatter chart.
    var valueAxis = ChartAxis(showsMajorGridlines: true)

    /// `nil` hides the legend.
    var legend: ChartLegendPosition? = .bottom
    var dataLabels = ChartDataLabels()
    /// The chart-wide text properties every label inherits.
    var textStyle = ChartTextStyle()
    var legendTextStyle = ChartTextStyle()

    /// One colour per point rather than per series. Pie charts default to it;
    /// it means nothing once a chart has more than one series.
    var variesColors = false
    /// Excel's default: rows and columns the user hid drop out of the plot.
    var plotsVisibleCellsOnly = true
    /// The space between clusters, as a percentage of a bar's width.
    var gapWidth: Int?
    /// How far bars in a cluster overlap, from -100 to 100.
    var overlap: Int?
    /// The doughnut's hole, as a percentage of its diameter.
    var holeSize = 50
    var firstSliceAngle = 0

    /// The chart area's fill. `nil` is Excel's default white paper.
    var backgroundColorHex: String?
    var hasBorder = true
    /// The schema's default when the element is absent is *rounded*, which is
    /// why charts from other generators often show soft corners in Excel.
    var hasRoundedCorners = false

    /// Where the chart sits on its worksheet. Ignored on a chart sheet, which
    /// the chart fills.
    var placement = ChartPlacement()

    /// The description screen readers announce: Excel's Alt Text.
    var altText: String?

    /// The chart as the file had it, when it came from one. Saving edits that
    /// XML rather than writing the chart afresh, so everything the model does
    /// not hold — gradients, marker shapes, manual layouts, label positions —
    /// survives a round trip untouched.
    var original: ChartOriginal?

    init(name: String, kind: ChartKind) {
        self.name = name
        self.kind = kind
    }
}

enum ChartKind: String, CaseIterable, Hashable, Sendable {
    case column
    case bar
    case line
    case area
    case pie
    case doughnut
    case scatter

    var label: String {
        switch self {
        case .column: return String(localized: "Chart.Kind.Column")
        case .bar: return String(localized: "Chart.Kind.Bar")
        case .line: return String(localized: "Chart.Kind.Line")
        case .area: return String(localized: "Chart.Kind.Area")
        case .pie: return String(localized: "Chart.Kind.Pie")
        case .doughnut: return String(localized: "Chart.Kind.Doughnut")
        case .scatter: return String(localized: "Chart.Kind.Scatter")
        }
    }

    var symbolName: String {
        switch self {
        case .column: return "chart.bar.xaxis"
        case .bar: return "chart.bar.horizontal.page"
        case .line: return "chart.xyaxis.line"
        case .area: return "chart.line.uptrend.xyaxis"
        case .pie: return "chart.pie"
        case .doughnut: return "circle.circle"
        case .scatter: return "chart.dots.scatter"
        }
    }

    /// Pie and doughnut charts have no axes and plot only their first series.
    var isRadial: Bool { self == .pie || self == .doughnut }

    /// Whether the chart can stack its series, and so has a grouping to pick.
    var supportsGrouping: Bool {
        switch self {
        case .column, .bar, .line, .area: return true
        case .pie, .doughnut, .scatter: return false
        }
    }
}

/// How the series of a column, bar, line or area chart share the plot.
///
/// For column and bar charts `.standard` is what the file calls `clustered`;
/// the file's own `standard` exists only for 3-D bars, which are not modelled.
enum ChartGrouping: String, CaseIterable, Hashable, Sendable {
    case standard
    case stacked
    case percentStacked

    var label: String {
        switch self {
        case .standard: return String(localized: "Chart.Grouping.Standard")
        case .stacked: return String(localized: "Chart.Grouping.Stacked")
        case .percentStacked: return String(localized: "Chart.Grouping.PercentStacked")
        }
    }
}

enum ChartLegendPosition: String, CaseIterable, Hashable, Sendable {
    case right = "r"
    case left = "l"
    case top = "t"
    case bottom = "b"
    case topRight = "tr"

    var label: String {
        switch self {
        case .right: return String(localized: "Chart.Legend.Right")
        case .left: return String(localized: "Chart.Legend.Left")
        case .top: return String(localized: "Chart.Legend.Top")
        case .bottom: return String(localized: "Chart.Legend.Bottom")
        case .topRight: return String(localized: "Chart.Legend.TopRight")
        }
    }
}

/// Font properties a chart label can carry. Every field is optional because
/// DrawingML text inherits: a label that names no size takes the chart's.
struct ChartTextStyle: Hashable, Sendable {
    /// In points.
    var fontSize: Double?
    var isBold: Bool?
    var isItalic: Bool?
    /// "AARRGGBB", like `CellStyle`'s colours.
    var colorHex: String?
    var fontName: String?

    var isEmpty: Bool { self == ChartTextStyle() }

    /// This style with anything it leaves unsaid taken from `parent`.
    func inheriting(from parent: ChartTextStyle) -> ChartTextStyle {
        ChartTextStyle(
            fontSize: fontSize ?? parent.fontSize,
            isBold: isBold ?? parent.isBold,
            isItalic: isItalic ?? parent.isItalic,
            colorHex: colorHex ?? parent.colorHex,
            fontName: fontName ?? parent.fontName
        )
    }
}

struct ChartTitle: Hashable, Sendable {
    var text: String
    /// A title that reads its text from a cell, as `=Sheet1!$A$1` in Excel's
    /// title box makes. `text` then holds the value last read from it.
    var reference: ChartReference?
    var textStyle = ChartTextStyle()

    init(text: String, reference: ChartReference? = nil, textStyle: ChartTextStyle = ChartTextStyle()) {
        self.text = text
        self.reference = reference
        self.textStyle = textStyle
    }
}

struct ChartAxis: Hashable, Sendable {
    /// Excel "deletes" an axis it is not showing; the scale still applies.
    var isVisible = true
    var title: ChartTitle?
    var showsMajorGridlines = false
    var minimum: Double?
    var maximum: Double?
    var majorUnit: Double?
    /// A number format for the tick labels. `nil` follows the source cells.
    var numberFormat: String?
    /// Values run from the far end: `maxMin` orientation.
    var isReversed = false
    /// Category axes over dates are date axes in the file, which space their
    /// points by time rather than evenly.
    var isDateAxis = false
    var textStyle = ChartTextStyle()

    init(showsMajorGridlines: Bool = false) {
        self.showsMajorGridlines = showsMajorGridlines
    }
}

struct ChartDataLabels: Hashable, Sendable {
    var showsValue = false
    var showsPercentage = false
    var showsCategoryName = false
    var showsSeriesName = false

    var isVisible: Bool { showsValue || showsPercentage || showsCategoryName || showsSeriesName }
}

struct ChartSeries: Identifiable, Hashable, Sendable {
    var id = UUID()
    var name = ChartSource()
    /// Category labels, or the X values of a scatter series.
    var categories = ChartSource()
    var values = ChartSource()
    /// "AARRGGBB". `nil` takes the theme's accent for the series' position.
    var colorHex: String?
    /// Per-point overrides, keyed by point index — chiefly pie slices.
    var pointColors: [Int: String] = [:]
    /// Line and scatter series only.
    var showsLine = true
    var showsMarkers = true
    var isSmooth = false
    /// Line width in points, when the file named one.
    var lineWidth: Double?
}

/// Where one dimension of a series — its name, categories or values — comes
/// from, in the three shapes the file allows.
struct ChartSource: Hashable, Sendable {
    /// A range of cells the chart follows live.
    var reference: ChartReference?
    /// A formula we cannot follow — a defined name, another workbook, a union
    /// of ranges — written back to the file exactly as it came.
    var formula: String?
    /// Literal values, or the values cached with a reference. What the chart
    /// shows when there is nothing live to read.
    var cache: [CellValue] = []
    /// The number format Excel stored with a numeric cache.
    var cacheFormat: String?

    init(reference: ChartReference? = nil, formula: String? = nil, cache: [CellValue] = []) {
        self.reference = reference
        self.formula = formula
        self.cache = cache
    }

    var isEmpty: Bool { reference == nil && formula == nil && cache.isEmpty }

    static func text(_ value: String) -> ChartSource { ChartSource(cache: [.text(value)]) }
}

/// A rectangular block of cells on a named sheet. The sheet is held by
/// identity, not name, so renaming it does not break the chart and the
/// reference is rebuilt with the current name whenever the file is written.
struct ChartReference: Hashable, Sendable {
    var sheetID: Worksheet.ID
    var range: CellRange

    init(sheetID: Worksheet.ID, range: CellRange) {
        self.sheetID = sheetID
        self.range = range.normalized
    }
}

/// A point on the sheet: a cell, and an offset into it in points.
struct ChartAnchor: Hashable, Sendable {
    var row: Int
    var column: Int
    var rowOffset: Double = 0
    var columnOffset: Double = 0
}

/// Where an embedded chart sits, as the two corners Excel's `twoCellAnchor`
/// pins it by, so that it moves and stretches with the cells beneath it.
struct ChartPlacement: Hashable, Sendable {
    var from = ChartAnchor(row: 1, column: 1)
    var to = ChartAnchor(row: 16, column: 7)
    /// Excel's `editAs`: whether the chart moves and sizes with its cells.
    /// Carried through rather than modelled.
    var editAs: String?
}

/// A chart part as it was read, with what the reader made of it.
///
/// Immutable and shared between copies of a chart: what a copy has changed is
/// found by comparing it with `baseline`, and only that is written into the
/// original XML.
final class ChartOriginal: Hashable, Sendable {
    /// The chart part's bytes.
    let xml: Data
    /// The model the reader built from `xml`, without its own `original`.
    let baseline: Chart
    /// The style and colour parts Excel keeps beside a chart.
    let companions: [ChartCompanion]
    /// The anchor's `nvGraphicFramePr` — name, alt text, locks — as written.
    let frameProperties: String?
    /// The anchor's `clientData`, which says whether the chart prints.
    let clientData: String?

    init(xml: Data, baseline: Chart, companions: [ChartCompanion], frameProperties: String?, clientData: String?) {
        var baseline = baseline
        baseline.original = nil
        self.xml = xml
        self.baseline = baseline
        self.companions = companions
        self.frameProperties = frameProperties
        self.clientData = clientData
    }

    static func == (lhs: ChartOriginal, rhs: ChartOriginal) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// A part a chart relates to that only Excel reads: its chart style or its
/// colour style. Carried through untouched.
struct ChartCompanion: Hashable, Sendable {
    var relationshipType: String
    var data: Data

    static let styleType = "http://schemas.microsoft.com/office/2011/relationships/chartStyle"
    static let colorsType = "http://schemas.microsoft.com/office/2011/relationships/chartColorStyle"

    /// The part's file stem and content type, which its type fixes.
    var stem: String { relationshipType == Self.styleType ? "style" : "colors" }
    var contentType: String {
        relationshipType == Self.styleType
            ? "application/vnd.ms-office.chartstyle+xml"
            : "application/vnd.ms-office.chartcolorstyle+xml"
    }
}

/// A non-chart object on a sheet's drawing — a picture, a shape, a chart type
/// we do not model — kept exactly as the file had it.
struct PreservedDrawingAnchor: Hashable, Sendable {
    /// The anchor element, namespace declarations and all.
    var xml: String
    /// The relationships the fragment names, by their original id. They are
    /// written back under the same ids, which is what lets the fragment be
    /// re-emitted without being rewritten.
    var relationships: [PreservedDrawingRelationship]
    /// The largest `cNvPr` id inside the fragment, so the shapes we add to the
    /// same drawing can be numbered clear of it.
    var largestShapeID: Int
    /// Where it sits, for drawing a placeholder in its place.
    var placement: ChartPlacement?
    /// Whether the fragment holds a chart rather than a picture or a shape.
    var isChart: Bool
    /// The image the fragment shows, when it is a picture we can draw.
    var picture: DrawingPicture?
}

/// A picture on a sheet's drawing: which image part it shows, and how much
/// of each side of the image it crops away.
struct DrawingPicture: Hashable, Sendable {
    /// The image part's path in the package.
    var target: String
    /// The fractions of the image cut from each edge — DrawingML's `srcRect`.
    var cropLeft = 0.0
    var cropTop = 0.0
    var cropRight = 0.0
    var cropBottom = 0.0
}

struct PreservedDrawingRelationship: Hashable, Sendable {
    var id: String
    var type: String
    /// The absolute package path of an internal target, or the URL of an
    /// external one.
    var target: String
    var isExternal: Bool

    /// A place in this workbook — `#'Sheet 2'!A1`, the target of a shape's
    /// in-workbook link — rather than a part of the package.
    var isLocation: Bool { !isExternal && target.hasPrefix("#") }

    /// Whether the target is a part the package must carry.
    var isPackagePart: Bool { !isExternal && !isLocation }
}
