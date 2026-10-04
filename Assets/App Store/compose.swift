#!/usr/bin/env swift

import AppKit

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let languages = ["en", "ja"]

/// Captures live in `Raw/<device>/<lang>/` and are written to `<device>/<lang>/`.
enum Device: String {
    case iPhone
    case iPad

    /// 6.5" iPhone and 13" iPad.
    var canvasSize: NSSize {
        switch self {
        case .iPhone: NSSize(width: 1242, height: 2688)
        case .iPad: NSSize(width: 2064, height: 2752)
        }
    }

    /// Text and margins are laid out for the iPhone canvas and scaled up by width.
    var scale: CGFloat { canvasSize.width / Device.iPhone.canvasSize.width }

    func rawDir(_ language: String) -> URL {
        scriptDir.appendingPathComponent("Raw").appendingPathComponent(rawValue)
            .appendingPathComponent(language)
    }

    func outDir(_ language: String) -> URL {
        scriptDir.appendingPathComponent(rawValue).appendingPathComponent(language)
    }
}

struct Copy {
    let header: String
    let caption: String
}

struct Screenshot {
    let name: String
    /// Keyed by language code. A language without copy is skipped.
    let copy: [String: Copy]
    let gradientTop: NSColor
    let gradientBottom: NSColor
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// The Tables green, the Kivotos sky, and the deep blue of the sheet headers.
let green = (color(0x4CC38A), color(0x1B7A4E))
let sky = (color(0x7CC8F8), color(0x2A78D4))
let navy = (color(0x4F6FB5), color(0x1F3864))

let functionsCopy = [
    "en": Copy(header: "Over 100 functions", caption: "SUMIFS, XLOOKUP, and results as you type"),
    "ja": Copy(header: "100以上の関数", caption: "SUMIFSもXLOOKUPも、入力と同時に計算"),
]
let formatCopy = [
    "en": Copy(header: "Formatting that stays put", caption: "Colours, borders, and fonts, saved as they are"),
    "ja": Copy(header: "書式もそのまま", caption: "色・罫線・フォントを保ったまま保存"),
]
let numberFormatCopy = [
    "en": Copy(header: "Numbers, your way", caption: "Currency, dates, percentages, or your own code"),
    "ja": Copy(header: "数値を思いどおりに", caption: "通貨・日付・パーセント、独自の書式も"),
]
let darkCopy = [
    "en": Copy(header: "Made for Dark Mode", caption: "Sheets that stay readable in the dark"),
    "ja": Copy(header: "ダークモードに対応", caption: "暗い画面でも見やすいシート"),
]

let iPhoneScreenshots = [
    Screenshot(
        name: "01-budget",
        copy: [
            "en": Copy(header: "Your spreadsheets, anywhere", caption: "Open and edit Excel and CSV files"),
            "ja": Copy(header: "表計算を、どこでも", caption: "ExcelやCSVをそのまま開いて編集"),
        ],
        gradientTop: sky.0, gradientBottom: sky.1
    ),
    Screenshot(name: "02-functions", copy: functionsCopy, gradientTop: green.0, gradientBottom: green.1),
    Screenshot(name: "03-format", copy: formatCopy, gradientTop: navy.0, gradientBottom: navy.1),
    Screenshot(name: "04-number-format", copy: numberFormatCopy, gradientTop: sky.0, gradientBottom: sky.1),
    Screenshot(name: "05-dark", copy: darkCopy, gradientTop: navy.0, gradientBottom: navy.1),
]

let iPadScreenshots = [
    Screenshot(
        name: "01-budget",
        copy: [
            "en": Copy(header: "Big sheets, on a big screen", caption: "A whole year of figures at a glance"),
            "ja": Copy(header: "大きな画面で、大きな表を", caption: "1年分の数字をひと目で"),
        ],
        gradientTop: sky.0, gradientBottom: sky.1
    ),
    Screenshot(
        name: "02-clubs",
        copy: [
            "en": Copy(header: "Formulas that keep up", caption: "Totals recalculate the moment you type"),
            "ja": Copy(header: "数式がすぐに反映", caption: "入力したそばから合計を再計算"),
        ],
        gradientTop: green.0, gradientBottom: green.1
    ),
    Screenshot(name: "03-functions", copy: functionsCopy, gradientTop: navy.0, gradientBottom: navy.1),
    Screenshot(name: "04-format", copy: formatCopy, gradientTop: sky.0, gradientBottom: sky.1),
    Screenshot(name: "05-number-format", copy: numberFormatCopy, gradientTop: green.0, gradientBottom: green.1),
    Screenshot(name: "06-dark", copy: darkCopy, gradientTop: navy.0, gradientBottom: navy.1),
]

// MARK: - Text

/// SF Pro Rounded. It has no Japanese, so that falls back to Tsukushi A Round
/// Gothic, which unlike Hiragino Maru Gothic comes in a bold to match the header.
func roundedFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let system = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
    let japanese = weight >= .semibold ? "TsukuARdGothic-Bold" : "TsukuARdGothic-Regular"
    let rounded = (system.withDesign(.rounded) ?? system).addingAttributes([
        .cascadeList: [NSFontDescriptor(name: japanese, size: size)],
    ])
    return NSFont(descriptor: rounded, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

/// One line of text at the largest size up to `size` that fits `maxWidth`.
struct Line {
    let text: String
    let attributes: [NSAttributedString.Key: Any]
    let font: NSFont
    let size: NSSize

    init(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, maxWidth: CGFloat) {
        var fontSize = size
        var font = roundedFont(ofSize: fontSize, weight: weight)
        var attributes: [NSAttributedString.Key: Any] = [:]
        var lineSize = NSSize.zero
        while fontSize > 10 {
            font = roundedFont(ofSize: fontSize, weight: weight)
            attributes = [.font: font, .foregroundColor: color]
            lineSize = (text as NSString).size(withAttributes: attributes)
            if lineSize.width <= maxWidth { break }
            fontSize -= 2
        }
        self.text = text
        self.attributes = attributes
        self.font = font
        self.size = lineSize
        (inkTop, inkBottom) = Line.inkInsets(of: text, attributes: attributes, size: lineSize)
    }

    /// How far below the top of the line box the glyphs actually start and end.
    let inkTop: CGFloat
    let inkBottom: CGFloat

    /// Centering by font metrics leaves the text looking off, since the line box carries
    /// space above the capitals and below the baseline. So the line is rendered once and
    /// the rows its glyphs cover are measured.
    private static func inkInsets(
        of text: String, attributes: [NSAttributedString.Key: Any], size: NSSize
    ) -> (CGFloat, CGFloat) {
        let width = Int(size.width.rounded(.up)), height = Int(size.height.rounded(.up))
        guard width > 0, height > 0, let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return (0, size.height) }
        bitmap.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        var opaque = attributes
        opaque[.foregroundColor] = NSColor.black
        (text as NSString).draw(at: .zero, withAttributes: opaque)
        NSGraphicsContext.restoreGraphicsState()

        // Bitmap rows run top to bottom.
        let inked = (0..<height).filter { y in
            (0..<width).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 }
        }
        guard let first = inked.first, let last = inked.last else { return (0, size.height) }
        return (CGFloat(first), CGFloat(last + 1))
    }

    /// Draws the line centered across `canvasWidth`, with the top of its line box at `top`.
    func draw(top: CGFloat, canvasWidth: CGFloat) {
        (text as NSString).draw(
            at: NSPoint(x: (canvasWidth - size.width) / 2, y: top - size.height),
            withAttributes: attributes
        )
    }
}

// MARK: - Device frames

func cgImage(of image: NSImage) -> CGImage {
    image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

/// Draws `raw` aspect-filled into `rect`.
func drawFilled(_ raw: CGImage, in rect: CGRect, context: CGContext) {
    let rawSize = CGSize(width: raw.width, height: raw.height)
    let scale = max(rect.width / rawSize.width, rect.height / rawSize.height)
    let drawSize = CGSize(width: rawSize.width * scale, height: rawSize.height * scale)
    context.draw(raw, in: CGRect(
        x: rect.midX - drawSize.width / 2,
        y: rect.midY - drawSize.height / 2,
        width: drawSize.width,
        height: drawSize.height
    ))
}

let hardwareImage = NSImage(contentsOf: scriptDir.appendingPathComponent("Hardware@2x.png"))!
let displayImage = NSImage(contentsOf: scriptDir.appendingPathComponent("Display@2x.png"))!
let hardwareCG = cgImage(of: hardwareImage)
let displayCG = cgImage(of: displayImage)
let hardwarePixel = NSSize(width: hardwareCG.width, height: hardwareCG.height)
let displayPixel = NSSize(width: displayCG.width, height: displayCG.height)
// The display mask sits centered within the hardware frame.
let displayOrigin = NSPoint(
    x: (hardwarePixel.width - displayPixel.width) / 2,
    y: (hardwarePixel.height - displayPixel.height) / 2
)

/// The raw capture clipped by the display mask, on a hardware-sized canvas.
func maskedScreen(raw: NSImage) -> NSImage {
    let image = NSImage(size: hardwarePixel)
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let displayRect = CGRect(origin: displayOrigin, size: displayPixel)
    ctx.clip(to: displayRect, mask: displayCG)
    drawFilled(cgImage(of: raw), in: displayRect, context: ctx)
    image.unlockFocus()
    return image
}

/// The iPad bezel, as a fraction of the device's width.
let iPadBezel: CGFloat = 0.03
let iPadCornerRadius: CGFloat = 0.05
/// 13" iPad Pro screen, width over height.
let iPadScreenAspect: CGFloat = 2064 / 2752

func deviceAspect(_ device: Device) -> CGFloat {
    switch device {
    case .iPhone:
        return hardwarePixel.width / hardwarePixel.height
    case .iPad:
        let screenHeight = (1 - 2 * iPadBezel) / iPadScreenAspect
        return 1 / (screenHeight + 2 * iPadBezel)
    }
}

/// A plain iPad Pro in black, drawn rather than imaged, with the capture on its screen.
func drawiPad(raw: NSImage, in rect: NSRect) {
    let ctx = NSGraphicsContext.current!.cgContext
    let bezel = rect.width * iPadBezel
    let outerRadius = rect.width * iPadCornerRadius

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 60
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.set()
    color(0x1C1C1E).setFill()
    NSBezierPath(roundedRect: rect, xRadius: outerRadius, yRadius: outerRadius).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // A lighter edge, as the aluminium band catches the light.
    let rim = NSBezierPath(
        roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: outerRadius - 2, yRadius: outerRadius - 2
    )
    rim.lineWidth = 4
    color(0x5A5A5E).setStroke()
    rim.stroke()

    let screenRect = rect.insetBy(dx: bezel, dy: bezel)
    let screenRadius = max(outerRadius - bezel * 0.8, 0)
    ctx.saveGState()
    NSBezierPath(roundedRect: screenRect, xRadius: screenRadius, yRadius: screenRadius).addClip()
    drawFilled(cgImage(of: raw), in: screenRect, context: ctx)
    ctx.restoreGState()
}

// MARK: - Composition

func compose(_ shot: Screenshot, language: String, device: Device) -> Bool {
    guard let copy = shot.copy[language] else { return true }
    let rawURL = device.rawDir(language).appendingPathComponent("\(shot.name).png")
    guard let raw = NSImage(contentsOf: rawURL) else {
        print("missing raw capture: \(rawURL.path)")
        return false
    }

    let canvasSize = device.canvasSize
    let s = device.scale
    let image = NSImage(size: canvasSize)
    image.lockFocus()

    NSGradient(starting: shot.gradientTop, ending: shot.gradientBottom)?
        .draw(in: NSRect(origin: .zero, size: canvasSize), angle: -90)

    // One-line header and caption. AppKit's origin is bottom-left.
    let textWidth = canvasSize.width - 96 * s
    let header = Line(copy.header, size: 84 * s, weight: .bold, color: .white, maxWidth: textWidth)
    let caption = Line(
        copy.caption, size: 44 * s, weight: .medium,
        color: NSColor.white.withAlphaComponent(0.92), maxWidth: textWidth
    )
    let captionGap = 4 * s
    // From the top of the header's ink to the bottom of the caption's.
    let inkHeight = header.size.height + captionGap + caption.inkBottom - header.inkTop

    let aspect = deviceAspect(device)
    var deviceSize: NSSize
    let deviceBottom: CGFloat
    let deviceTop: CGFloat
    switch device {
    case .iPhone:
        // The device fills what is left below a band that holds the text.
        let textPadding = 88 * s
        let deviceBottomMargin = 88 * s
        deviceTop = canvasSize.height - inkHeight - 2 * textPadding
        let availableHeight = deviceTop - deviceBottomMargin
        deviceSize = NSSize(width: availableHeight * aspect, height: availableHeight)
        if deviceSize.width > canvasSize.width - 120 * s {
            deviceSize.width = canvasSize.width - 120 * s
            deviceSize.height = deviceSize.width / aspect
        }
        deviceBottom = deviceTop - deviceSize.height
    case .iPad:
        // The iPad is drawn as wide as the margins allow and runs off the bottom of the
        // canvas, leaving a band above it for the text.
        deviceSize = NSSize(width: canvasSize.width - 140 * s, height: (canvasSize.width - 140 * s) / aspect)
        deviceTop = canvasSize.height - 300 * s
        deviceBottom = deviceTop - deviceSize.height
    }

    // The text's ink is centered in the band between the top of the canvas and the device.
    let inkTop = (canvasSize.height + deviceTop + inkHeight) / 2
    let headerTop = (inkTop + header.inkTop).rounded()
    header.draw(top: headerTop, canvasWidth: canvasSize.width)
    caption.draw(top: headerTop - header.size.height - captionGap, canvasWidth: canvasSize.width)

    let deviceRect = NSRect(
        x: ((canvasSize.width - deviceSize.width) / 2).rounded(),
        y: deviceBottom.rounded(),
        width: deviceSize.width,
        height: deviceSize.height
    )

    switch device {
    case .iPhone:
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 60
        shadow.shadowOffset = NSSize(width: 0, height: -24)
        shadow.set()
        hardwareImage.draw(in: deviceRect)
        NSGraphicsContext.current?.restoreGraphicsState()
        maskedScreen(raw: raw).draw(in: deviceRect)
    case .iPad:
        drawiPad(raw: raw, in: deviceRect)
    }

    image.unlockFocus()

    // Rasterize at exactly the canvas size in pixels.
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width), pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return false }
    bitmap.size = canvasSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(origin: .zero, size: canvasSize))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
    let outDir = device.outDir(language)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let outURL = outDir.appendingPathComponent("\(shot.name).png")
    do {
        try png.write(to: outURL)
        print("wrote \(outURL.path.replacingOccurrences(of: scriptDir.path + "/", with: ""))")
        return true
    } catch {
        print("failed to write \(outURL.path): \(error)")
        return false
    }
}

var allOK = true
for language in languages {
    for shot in iPhoneScreenshots {
        allOK = compose(shot, language: language, device: .iPhone) && allOK
    }
    for shot in iPadScreenshots {
        allOK = compose(shot, language: language, device: .iPad) && allOK
    }
}
exit(allOK ? 0 : 1)
