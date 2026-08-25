import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift flatten_icon.swift <transparent-input.png> <rounded-white-output.png>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL
guard let source = CGImageSourceCreateWithURL(inputURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    fputs("Unable to read or prepare input PNG\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Unable to create RGBA canvas\n", stderr)
    exit(1)
}

let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
let scale = CGFloat(min(width, height)) / 1254
let inset = 10 * scale
let cornerRadius = 200 * scale
let whiteBackground = CGPath(
    roundedRect: bounds.insetBy(dx: inset, dy: inset),
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)
context.saveGState()
context.addPath(whiteBackground)
context.clip()
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(bounds)
context.interpolationQuality = .none
context.draw(image, in: bounds)
context.restoreGState()

guard let flattened = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("Unable to create output PNG\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, flattened, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to encode output PNG\n", stderr)
    exit(1)
}
print((outputURL as URL).path)
