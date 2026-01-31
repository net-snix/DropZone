import AppKit
import SwiftUI

final class NoiseTexture {
    static let shared = NoiseTexture()
    let image: NSImage

    private init() {
        image = Self.makeImage(size: 160)
    }

    private static func makeImage(size: Int) -> NSImage {
        let width = size
        let height = size
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = UInt8.random(in: 0...255)
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
            pixels[index + 3] = 32
        }

        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider, let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return NSImage(size: NSSize(width: width, height: height))
        }

        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }
}

struct NoiseOverlay: View {
    var opacity: Double = 0.12

    var body: some View {
        Image(nsImage: NoiseTexture.shared.image)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
