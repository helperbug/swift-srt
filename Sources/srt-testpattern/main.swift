//
//  srt-testpattern
//
//  Emits raw BGRA frames to stdout for ffmpeg to encode. Every frame carries
//  its own number and clock, large, plus a sweeping bar: a skipped number is
//  a dropped frame, a jumped bar is a stutter. Nothing here needs freetype.
//
//  Usage: srt-testpattern [--frames 1800] [--fps 30] [--width 1280] [--height 720]
//         | ffmpeg -f rawvideo -pix_fmt bgra -s 1280x720 -r 30 -i - ...
//

import CoreGraphics
import CoreText
import Foundation

var frames = 1800
var fps = 30
var width = 1280
var height = 720

let arguments = Array(CommandLine.arguments.dropFirst())
for (index, argument) in arguments.enumerated() {
    let next = index + 1 < arguments.count ? arguments[index + 1] : nil
    switch argument {
    case "--frames": if let next, let v = Int(next) { frames = v }
    case "--fps":    if let next, let v = Int(next) { fps = v }
    case "--width":  if let next, let v = Int(next) { width = v }
    case "--height": if let next, let v = Int(next) { height = v }
    default: break
    }
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bytesPerRow = width * 4

guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: bytesPerRow, space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
    FileHandle.standardError.write(Data("could not create bitmap context\n".utf8))
    exit(1)
}

let bigFont = CTFontCreateWithName("Menlo-Bold" as CFString, CGFloat(height) * 0.42, nil)
let smallFont = CTFontCreateWithName("Menlo-Bold" as CFString, CGFloat(height) * 0.09, nil)

func draw(_ text: String, font: CTFont, at point: CGPoint, color: CGColor) {
    let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
    context.textPosition = point
    CTLineDraw(line, context)
}

func centeredWidth(_ text: String, font: CTFont) -> CGFloat {
    let attributes: [CFString: Any] = [kCTFontAttributeName: font]
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let yellow = CGColor(red: 1, green: 0.85, blue: 0.1, alpha: 1)
let cyan = CGColor(red: 0.2, green: 0.9, blue: 1, alpha: 1)
let beat = [CGColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 1), CGColor(red: 0.2, green: 0.95, blue: 0.3, alpha: 1)]

let output = FileHandle.standardOutput
let w = CGFloat(width), h = CGFloat(height)

for frame in 0..<frames {

    /// Background: a subtle hue that drifts with time, so a frozen picture is
    /// visible even without reading the number.
    let hue = CGFloat(frame % (fps * 20)) / CGFloat(fps * 20)
    context.setFillColor(CGColor(red: 0.08 + 0.06 * hue, green: 0.08, blue: 0.14 - 0.06 * hue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))

    /// Sweeping bar: one full sweep every 4 seconds. Any hitch shows as a jump.
    let sweep = CGFloat(frame % (fps * 4)) / CGFloat(fps * 4)
    context.setFillColor(cyan)
    context.fill(CGRect(x: sweep * (w - 24), y: 0, width: 24, height: h * 0.08))
    context.fill(CGRect(x: sweep * (w - 24), y: h * 0.92, width: 24, height: h * 0.08))

    /// Beat square: alternates colour every second, at the top left.
    context.setFillColor(beat[(frame / fps) % 2])
    context.fill(CGRect(x: 32, y: h - 32 - h * 0.12, width: h * 0.12, height: h * 0.12))

    /// Frame number, huge and centred.
    let number = String(format: "%05d", frame)
    let numberWidth = centeredWidth(number, font: bigFont)
    draw(number, font: bigFont, at: CGPoint(x: (w - numberWidth) / 2, y: h * 0.36), color: white)

    /// Clock, mm:ss.mmm.
    let totalMs = frame * 1000 / fps
    let clock = String(format: "%02d:%02d.%03d", totalMs / 60000, (totalMs / 1000) % 60, totalMs % 1000)
    let clockWidth = centeredWidth(clock, font: smallFont)
    draw(clock, font: smallFont, at: CGPoint(x: (w - clockWidth) / 2, y: h * 0.20), color: yellow)

    draw("\(fps) fps", font: smallFont, at: CGPoint(x: w - 32 - centeredWidth("\(fps) fps", font: smallFont), y: h - 32 - h * 0.09), color: white)

    guard let data = context.data else { exit(1) }
    output.write(Data(bytes: data, count: bytesPerRow * height))
}
