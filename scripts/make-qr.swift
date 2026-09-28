// make-qr.swift: a QR code for one URL, as an SVG and a PNG, made with Apple's
// own encoder (Core Image's CIQRCodeGenerator) and checked by decoding it
// back with Apple's QR detector before anything is written.
//
//   swift scripts/make-qr.swift <url> <out-basename>
//   swift scripts/make-qr.swift https://fxe-tennis-admin.vercel.app/app web/app-qr
//
// Why this and not a library (2026-09-28): nothing on the machine could draw
// a QR code, and adding one means downloading a package. Core Image ships
// with macOS, and a decode check with CIDetector proves the code says what we
// meant: a QR code that scans to the wrong place is worse than none.
//
// Correction level "Q" (25% of the code can be damaged): the code will be
// printed on a card at the party and put in emails, so it gets folded,
// smudged and photographed at an angle.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: swift scripts/make-qr.swift <url> <out-basename>\n".data(using: .utf8)!)
    exit(2)
}
let url = args[1]
let base = args[2]

let filter = CIFilter.qrCodeGenerator()
filter.message = Data(url.utf8)
filter.correctionLevel = "Q"
guard let modulesImage = filter.outputImage else { fatalError("no QR image") }

// One pixel per module, black on white.
let context = CIContext()
let extent = modulesImage.extent.integral
guard let cg = context.createCGImage(modulesImage, from: extent) else { fatalError("no bitmap") }
let n = cg.width
var gray = [UInt8](repeating: 255, count: n * n)
let space = CGColorSpaceCreateDeviceGray()
gray.withUnsafeMutableBytes { buf in
    let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8,
                        bytesPerRow: n, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
}
func dark(_ x: Int, _ y: Int) -> Bool { gray[y * n + x] < 128 }

// SVG: one rect per run of dark modules in a row, plus a 4-module quiet zone
// (the standard's minimum), navy on white so it matches the brand yet stays
// high contrast for any phone camera.
let quiet = 4
let size = n + 2 * quiet
var rects = ""
for y in 0..<n {
    var x = 0
    while x < n {
        if dark(x, y) {
            var run = 1
            while x + run < n && dark(x + run, y) { run += 1 }
            rects += "<rect x=\"\(x + quiet)\" y=\"\(y + quiet)\" width=\"\(run)\" height=\"1\"/>"
            x += run
        } else { x += 1 }
    }
}
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(size) \(size)" shape-rendering="crispEdges" role="img" aria-label="QR code for \(url)">
<rect width="\(size)" height="\(size)" fill="#FFFFFF"/>
<g fill="#0A1B3D">\(rects)</g>
</svg>

"""

// PNG at 24 pixels per module, for emails and print.
let scale = 24
let px = size * scale
var png = [UInt8](repeating: 255, count: px * px * 4)
for y in 0..<px {
    for x in 0..<px {
        let mx = x / scale - quiet, my = y / scale - quiet
        let isDark = mx >= 0 && my >= 0 && mx < n && my < n && dark(mx, my)
        let i = (y * px + x) * 4
        if isDark { png[i] = 0x0A; png[i + 1] = 0x1B; png[i + 2] = 0x3D }
        png[i + 3] = 255
    }
}
let rgb = CGColorSpaceCreateDeviceRGB()
let pngImage: CGImage = png.withUnsafeMutableBytes { buf in
    CGContext(data: buf.baseAddress, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
              space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}

// Decode what we drew, before writing anything.
let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
let found = detector.features(in: CIImage(cgImage: pngImage)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
guard found == [url] else {
    FileHandle.standardError.write("decode check FAILED: read \(found), expected [\(url)]\n".data(using: .utf8)!)
    exit(1)
}

try svg.write(toFile: base + ".svg", atomically: true, encoding: .utf8)
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: base + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, pngImage, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("PNG not written") }
print("\(n)x\(n) modules, level Q; decoded back as \(found[0]); wrote \(base).svg and \(base).png (\(px)px)")
