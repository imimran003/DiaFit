import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: chroma-key.swift <input.png> <output.png>\n", stderr)
    exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Could not read \(inputURL.path)\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Could not create pixel context\n", stderr)
    exit(1)
}

context.interpolationQuality = .high
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
    let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

for index in stride(from: 0, to: pixels.count, by: 4) {
    let red = Float(pixels[index])
    let green = Float(pixels[index + 1])
    let blue = Float(pixels[index + 2])
    let distance = sqrt(red * red + pow(255 - green, 2) + blue * blue)
    let alpha = smoothstep(24, 170, distance)

    // Despill green at antialiased boundaries before premultiplying.
    let neutralGreen = max(red, blue) + (green - max(red, blue)) * alpha
    pixels[index] = UInt8(min(max(red * alpha, 0), 255))
    pixels[index + 1] = UInt8(min(max(neutralGreen * alpha, 0), 255))
    pixels[index + 2] = UInt8(min(max(blue * alpha, 0), 255))
    pixels[index + 3] = UInt8(min(max(alpha * 255, 0), 255))
}

guard
    let keyedImage = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
    fputs("Could not prepare PNG output\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, keyedImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Could not write \(outputURL.path)\n", stderr)
    exit(1)
}
