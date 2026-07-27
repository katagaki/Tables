import AppKit
import CoreGraphics
import Foundation

// Renders the Tables app icon into PNGs for the asset catalog. The artwork
// mirrors Assets/Tables.icon/Assets/Grid.svg: a two-by-three table whose cells
// step through opacity, rounded only at the block's four outer corners.
//
//   swift Assets/RenderIcon.swift Assets/Rendered

let canvas: CGFloat = 1024
let cornerRadius: CGFloat = 48

struct CellSpec {
    var x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
    var opacity: CGFloat
    /// Which of the cell's corners fall on the table's outer edge.
    var topLeft = false, topRight = false, bottomRight = false, bottomLeft = false
}

let cells: [CellSpec] = [
    .init(x: 188, y: 244, width: 316, height: 168, opacity: 0.95, topLeft: true),
    .init(x: 520, y: 244, width: 316, height: 168, opacity: 0.55, topRight: true),
    .init(x: 188, y: 428, width: 316, height: 168, opacity: 0.72),
    .init(x: 520, y: 428, width: 316, height: 168, opacity: 0.95),
    .init(x: 188, y: 612, width: 316, height: 168, opacity: 0.45, bottomLeft: true),
    .init(x: 520, y: 612, width: 316, height: 168, opacity: 0.78, bottomRight: true),
]

/// A rectangle rounded on only the corners the cell shares with the table's edge.
func path(for cell: CellSpec) -> CGPath {
    let path = CGMutablePath()
    let (x, y, w, h) = (cell.x, cell.y, cell.width, cell.height)
    let tl = cell.topLeft ? cornerRadius : 0
    let tr = cell.topRight ? cornerRadius : 0
    let br = cell.bottomRight ? cornerRadius : 0
    let bl = cell.bottomLeft ? cornerRadius : 0

    path.move(to: CGPoint(x: x + tl, y: y))
    path.addLine(to: CGPoint(x: x + w - tr, y: y))
    if tr > 0 {
        path.addArc(tangent1End: CGPoint(x: x + w, y: y),
                    tangent2End: CGPoint(x: x + w, y: y + tr), radius: tr)
    }
    path.addLine(to: CGPoint(x: x + w, y: y + h - br))
    if br > 0 {
        path.addArc(tangent1End: CGPoint(x: x + w, y: y + h),
                    tangent2End: CGPoint(x: x + w - br, y: y + h), radius: br)
    }
    path.addLine(to: CGPoint(x: x + bl, y: y + h))
    if bl > 0 {
        path.addArc(tangent1End: CGPoint(x: x, y: y + h),
                    tangent2End: CGPoint(x: x, y: y + h - bl), radius: bl)
    }
    path.addLine(to: CGPoint(x: x, y: y + tl))
    if tl > 0 {
        path.addArc(tangent1End: CGPoint(x: x, y: y),
                    tangent2End: CGPoint(x: x + tl, y: y), radius: tl)
    }
    path.closeSubpath()
    return path
}

/// `inset` is the transparent margin macOS icons sit inside, as a fraction of
/// the canvas; iOS passes 0 and draws full-bleed.
func drawIcon(into context: CGContext, size: CGFloat, inset: CGFloat, rounded: Bool) {
    let scale = size / canvas
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    // Flip to the SVG's top-left origin.
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)

    // Shrink the artwork into the tile so the margin stays clear.
    let margin = canvas * inset
    let tile = canvas - margin * 2
    context.translateBy(x: margin, y: margin)
    context.scaleBy(x: tile / canvas, y: tile / canvas)

    if rounded {
        context.addPath(CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: canvas, height: canvas),
            cornerWidth: canvas * 0.2237, cornerHeight: canvas * 0.2237, transform: nil
        ))
        context.clip()
    }

    // Green gradient background, lighter at the top.
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.216, green: 0.741, blue: 0.427, alpha: 1),
            CGColor(red: 0.043, green: 0.475, blue: 0.271, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: canvas), options: []
    )

    for cell in cells {
        context.addPath(path(for: cell))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: cell.opacity))
        context.fillPath()
    }
    context.restoreGState()
}

func makeImage(size: CGFloat, inset: CGFloat, rounded: Bool) -> Data {
    let width = Int(size)
    let context = CGContext(
        data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawIcon(into: context, size: size, inset: inset, rounded: rounded)
    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// iOS wants a full-bleed square; macOS wants the rounded tile inside a margin.
try makeImage(size: 1024, inset: 0, rounded: false)
    .write(to: outputDirectory.appending(path: "AppIcon-iOS-1024.png"))

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try makeImage(size: CGFloat(size), inset: 0.0977, rounded: true)
        .write(to: outputDirectory.appending(path: "AppIcon-macOS-\(size).png"))
}
print("rendered")
