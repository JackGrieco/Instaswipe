// Builds the export tutorial screenshots (TutorialStepNN) from the raw iPhone captures:
// crops away status and browser bars, covers personal data, outlines the element to tap.
//
// usage: swift tools/tutorial-screenshots.swift <dir with IMG_*.PNG> InstaSwipe/Assets.xcassets/Tutorial
//
// Coordinates are in 414-pt-wide preview units (a 1320×2868 capture shown 414×900),
// scaled to the real capture size. Check every output by eye before committing:
// no username, photo, email, phone number or birth date may stay readable.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Job {
    let source: String
    let step: Int
    /// Vertical band of the capture to keep.
    let keep: ClosedRange<CGFloat>
    let covers: [CGRect]
    var isDark = false
    /// The element to tap, outlined in the brand pink.
    var highlight: CGRect?
}

let usernameLine = { (y0: CGFloat, y1: CGFloat) in CGRect(x: 16, y: y0, width: 200, height: y1 - y0) }

let jobs = [
    Job(source: "IMG_7739", step: 1, keep: 50...292, covers: [
        CGRect(x: 125, y: 68, width: 160, height: 30),
        CGRect(x: 6, y: 104, width: 102, height: 114),
        CGRect(x: 112, y: 126, width: 116, height: 26),
        CGRect(x: 112, y: 154, width: 250, height: 40),
        CGRect(x: 10, y: 220, width: 160, height: 44)
    ], isDark: true, highlight: CGRect(x: 354, y: 60, width: 48, height: 44)),
    Job(source: "IMG_7740", step: 2, keep: 50...345, covers: [], isDark: true,
        highlight: CGRect(x: 8, y: 206, width: 398, height: 84)),
    Job(source: "IMG_7741", step: 3, keep: 70...840, covers: [
        CGRect(x: 60, y: 349, width: 190, height: 22),
        CGRect(x: 286, y: 346, width: 78, height: 46)
    ], isDark: true, highlight: CGRect(x: 18, y: 529, width: 378, height: 48)),
    Job(source: "IMG_7742", step: 4, keep: 70...800, covers: [
        CGRect(x: 28, y: 214, width: 140, height: 22)
    ], isDark: true, highlight: CGRect(x: 18, y: 274, width: 378, height: 49)),
    Job(source: "IMG_7744", step: 5, keep: 116...455, covers: [],
        highlight: CGRect(x: 14, y: 322, width: 386, height: 52)),
    Job(source: "IMG_7745", step: 6, keep: 116...812, covers: [usernameLine(185, 205)],
        highlight: CGRect(x: 19, y: 343, width: 376, height: 49)),
    Job(source: "IMG_7747", step: 7, keep: 80...900, covers: [],
        highlight: CGRect(x: 19, y: 568, width: 376, height: 49)),
    Job(source: "IMG_7748", step: 8, keep: 80...900, covers: [usernameLine(152, 174)],
        highlight: CGRect(x: 19, y: 520, width: 376, height: 57)),
    Job(source: "IMG_7749", step: 9, keep: 80...900, covers: [usernameLine(152, 174)],
        highlight: CGRect(x: 19, y: 296, width: 376, height: 74)),
    Job(source: "IMG_7750", step: 10, keep: 80...900, covers: [usernameLine(152, 174)],
        highlight: CGRect(x: 19, y: 438, width: 376, height: 49)),
    Job(source: "IMG_7753", step: 11, keep: 116...812, covers: [
        CGRect(x: 33, y: 234, width: 62, height: 64),
        CGRect(x: 100, y: 238, width: 120, height: 22),
        CGRect(x: 84, y: 369, width: 191, height: 22)
    ], highlight: CGRect(x: 14, y: 750, width: 386, height: 52)),
    Job(source: "IMG_7751", step: 12, keep: 80...900, covers: [
        CGRect(x: 33, y: 190, width: 62, height: 60),
        CGRect(x: 100, y: 192, width: 120, height: 20)
    ], highlight: CGRect(x: 283, y: 199, width: 102, height: 44)),
    Job(source: "IMG_7754", step: 13, keep: 62...900, covers: [], isDark: true,
        highlight: CGRect(x: 329, y: 83, width: 72, height: 50))
]

let previewWidth: CGFloat = 414
let outputWidth: CGFloat = 750
let lightCover = CGColor(red: 0xE6 / 255, green: 0xE3 / 255, blue: 0xEA / 255, alpha: 1)
let darkCover = CGColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
let highlightColor = CGColor(red: 0xE8 / 255, green: 0x30 / 255, blue: 0x7A / 255, alpha: 1)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(url.path)") }
    return image
}

func render(_ job: Job, from image: CGImage) -> CGImage {
    let k = CGFloat(image.width) / previewWidth
    let cropTop = job.keep.lowerBound * k
    let cropHeight = min(job.keep.upperBound * k, CGFloat(image.height)) - cropTop
    let scale = outputWidth / CGFloat(image.width)
    let size = CGSize(width: outputWidth, height: (cropHeight * scale).rounded())
    guard let ctx = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot create context") }
    ctx.interpolationQuality = .high
    // Flip to a top-left origin so preview coordinates map top-down.
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: 0, y: -cropTop)
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(image.height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    ctx.restoreGState()

    let scaled = { (r: CGRect) in CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k) }
    ctx.setFillColor(job.isDark ? darkCover : lightCover)
    for cover in job.covers {
        ctx.addPath(CGPath(roundedRect: scaled(cover), cornerWidth: 8 * k, cornerHeight: 8 * k, transform: nil))
        ctx.fillPath()
    }
    if let highlight = job.highlight {
        ctx.setStrokeColor(highlightColor)
        ctx.setLineWidth(3.5 * k)
        ctx.addPath(CGPath(roundedRect: scaled(highlight), cornerWidth: 12 * k, cornerHeight: 12 * k, transform: nil))
        ctx.strokePath()
    }
    guard let output = ctx.makeImage() else { fail("cannot render \(job.source)") }
    return output
}

func writeImageSet(_ image: CGImage, named name: String, in directory: URL) throws {
    let setDir = directory.appendingPathComponent(name + ".imageset")
    try FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)
    let pngURL = setDir.appendingPathComponent(name + ".png")
    guard let destination = CGImageDestinationCreateWithURL(pngURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot write \(pngURL.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot finalize \(pngURL.path)") }
    let contents = """
    {
      "images" : [ { "filename" : "\(name).png", "idiom" : "universal" } ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
    try contents.write(to: setDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: swift tools/tutorial-screenshots.swift <captures dir> <asset dir>") }
let sourceDir = URL(fileURLWithPath: arguments[1])
let assetDir = URL(fileURLWithPath: arguments[2])

for job in jobs {
    let image = loadImage(sourceDir.appendingPathComponent(job.source + ".PNG"))
    let name = String(format: "TutorialStep%02d", job.step)
    let output = render(job, from: image)
    try writeImageSet(output, named: name, in: assetDir)
    print("\(name) ← \(job.source) \(output.width)x\(output.height)")
}
