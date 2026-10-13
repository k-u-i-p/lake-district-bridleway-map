// Draws the Bens Mapper app icons (light, dark and tinted 1024×1024 PNGs) into the iOS asset catalog.
//
//   swift tools/make_app_icon.swift
//
// The design: contour lines of a fell, with a planned loop (yellow, as in the app) ridden from a red start pin.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("ios/LakeDistrictBridleways/Assets.xcassets/AppIcon.appiconset")

struct Palette {
    var backgroundTop: CGColor
    var backgroundBottom: CGColor
    var contour: CGColor
    var indexContour: CGColor
    var routeCasing: CGColor
    var route: CGColor
    var pin: CGColor
    var pinCentre: CGColor
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

let light = Palette(backgroundTop: rgb(0x2f6b4f), backgroundBottom: rgb(0x123326),
                    contour: rgb(0xffffff, 0.13), indexContour: rgb(0xffffff, 0.24),
                    routeCasing: rgb(0x000000, 0.35), route: rgb(0xffd400),
                    pin: rgb(0xe41b23), pinCentre: rgb(0xffffff))
let dark = Palette(backgroundTop: rgb(0x1b1f26), backgroundBottom: rgb(0x0c0e12),
                   contour: rgb(0x3ddc84, 0.12), indexContour: rgb(0x3ddc84, 0.24),
                   routeCasing: rgb(0x000000, 0.5), route: rgb(0xffd400),
                   pin: rgb(0xe41b23), pinCentre: rgb(0xffffff))
// Tinted icons are greyscale on black; iOS applies the tint from luminance.
let tinted = Palette(backgroundTop: rgb(0x000000), backgroundBottom: rgb(0x000000),
                     contour: rgb(0xffffff, 0.16), indexContour: rgb(0xffffff, 0.3),
                     routeCasing: rgb(0x000000, 0.6), route: rgb(0xffffff),
                     pin: rgb(0xb4b4b4), pinCentre: rgb(0x000000))

/// The `k`th contour ring around a summit. Rings are scaled copies of one wobbly outline plus a small
/// per-ring ripple (well under the ring spacing), so neighbouring rings never cross.
func contour(centre: CGPoint, ring k: Int, spacing: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let steps = 240
    let kf = CGFloat(k)
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let shape = 1 + 0.10 * sin(3 * t + 0.4) + 0.05 * sin(5 * t + 1.3) + 0.04 * sin(2 * t - 0.7)
        let ripple = spacing * 0.28 * sin(4 * t + kf * 0.55) * min(1, kf / 4)
        let r = kf * spacing * shape + ripple
        let p = CGPoint(x: centre.x + r * cos(t), y: centre.y + r * 0.82 * sin(t))
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

/// A smooth closed curve through the points (centripetal-ish Catmull–Rom as cubic Béziers).
func loop(through pts: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    let n = pts.count
    path.move(to: pts[0])
    for i in 0..<n {
        let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.addCurve(to: p2, control1: c1, control2: c2)
    }
    path.closeSubpath()
    return path
}

/// A map pin whose point sits on `tip`.
func pin(tip: CGPoint, headRadius r: CGFloat) -> (outline: CGPath, centre: CGPoint) {
    let centre = CGPoint(x: tip.x, y: tip.y - r * 1.75)
    let path = CGMutablePath()
    // Tangent points from the tip to the head circle.
    let d = tip.y - centre.y
    let a = asin(r / d)
    let tangentAngle = CGFloat.pi / 2 - a  // measured from +x, y down
    path.move(to: tip)
    path.addLine(to: CGPoint(x: centre.x + r * cos(tangentAngle), y: centre.y + r * sin(tangentAngle)))
    path.addArc(center: centre, radius: r, startAngle: tangentAngle, endAngle: .pi - tangentAngle, clockwise: true)
    path.closeSubpath()
    return (path, centre)
}

func draw(_ palette: Palette, to name: String) throws {
    let s = CGFloat(size)
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("no context") }
    // Work in a y-down space like the rest of the app's drawing.
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let gradient = CGGradient(colorsSpace: nil, colors: [palette.backgroundTop, palette.backgroundBottom] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s * 0.3, y: s),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // One fell, its summit inside the loop; enough rings to reach every corner.
    for k in 1...20 {
        ctx.addPath(contour(centre: CGPoint(x: 600, y: 470), ring: k, spacing: 54))
        let index = k % 5 == 0
        ctx.setStrokeColor(index ? palette.indexContour : palette.contour)
        ctx.setLineWidth(index ? 10 : 6)
        ctx.strokePath()
    }

    let route = loop(through: [
        CGPoint(x: 290, y: 610), CGPoint(x: 300, y: 420), CGPoint(x: 430, y: 300), CGPoint(x: 560, y: 330),
        CGPoint(x: 700, y: 230), CGPoint(x: 810, y: 360), CGPoint(x: 770, y: 560), CGPoint(x: 800, y: 720),
        CGPoint(x: 620, y: 800), CGPoint(x: 450, y: 730),
    ])
    ctx.addPath(route)
    ctx.setStrokeColor(palette.routeCasing)
    ctx.setLineWidth(76)
    ctx.strokePath()
    ctx.addPath(route)
    ctx.setStrokeColor(palette.route)
    ctx.setLineWidth(52)
    ctx.strokePath()

    let marker = pin(tip: CGPoint(x: 290, y: 610), headRadius: 92)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: rgb(0x000000, 0.45))
    ctx.addPath(marker.outline)
    ctx.setFillColor(palette.pin)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addEllipse(in: CGRect(x: marker.centre.x - 36, y: marker.centre.y - 36, width: 72, height: 72))
    ctx.setFillColor(palette.pinCentre)
    ctx.fillPath()

    let image = ctx.makeImage()!
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
    print("wrote \(url.path)")
}

try draw(light, to: "AppIcon.png")
try draw(dark, to: "AppIcon-Dark.png")
try draw(tinted, to: "AppIcon-Tinted.png")
