import SwiftUI
import Testing
import UIKit
@testable import WindRun

@MainActor
struct WorkoutGlyphTests {
    /// Compare painted bounds at the same font size, including transparent symbol margins.
    private func nativePaintedSize(_ symbol: String, at points: CGFloat) throws -> CGSize {
        let configuration = UIImage.SymbolConfiguration(pointSize: points, weight: .regular)
        let symbol = try #require(UIImage(systemName: symbol, withConfiguration: configuration))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: symbol.size, format: format)
        let rendered = renderer.image { _ in
            symbol.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: .zero)
        }
        return try paintedBounds(of: #require(rendered.cgImage))
    }

    private func paintedSize(_ symbol: String, at points: CGFloat) throws -> CGSize {
        let glyph = WorkoutGlyph(value: symbol).font(.system(size: points)).foregroundStyle(.black).fixedSize().padding(4)
        // On a busy CI runner ImageRenderer can draw an asset-catalog symbol blank while the catalog is
        // still loading. A blank result is drawn again a few times; a glyph that stays blank still fails.
        var size = CGSize.zero
        for _ in 0..<5 {
            let renderer = ImageRenderer(content: glyph)
            renderer.scale = 3
            size = try paintedBounds(of: #require(renderer.cgImage))
            if size.width > 0 && size.height > 0 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return size
    }

    private func paintedBounds(of image: CGImage) throws -> CGSize {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var bounds = CGRect.null
            for y in 0..<height {
                for x in 0..<width where buffer[(y * width + x) * 4 + 3] > 32 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            return bounds.size
        }
    }

    @Test func customAnimalsAndPancakesHaveTheFootprintOfANativeIcon() throws {
        let custom = WorkoutIcon.identifiers.filter { $0.hasPrefix("workout.") }.sorted()
        // Load every custom glyph from the catalog before measuring, so the first render isn't drawn mid-load.
        for id in custom { _ = UIImage(named: id) }
        for points: CGFloat in [17, 28] {
            let native = try nativePaintedSize("bird.fill", at: points)
            try #require(native.width > 0 && native.height > 0)
            for id in custom {
                let size = try paintedSize(id, at: points)
                let ratio = max(size.width, size.height) / max(native.width, native.height)
                #expect((0.85...1.20).contains(ratio), "\(id) at \(points) pt: \(size) vs \(native)")
            }
        }
    }

    @Test func emojiNamesDriveTheDefaultSuggestionAndPickerSearch() {
        #expect(WorkoutIconQuery("Hill🏃🏽‍♀️🇨🇦").emojiNames == ["woman running: medium skin tone", "flag: Canada"])
        #expect(WorkoutIconQuery("Snow ❄").emojiNames == ["snowflake"])
        for (name, symbol) in [("🔥", "flame.fill"), ("🐢", "tortoise.fill"), ("🏃🏽‍♀️", "figure.run"),
                               ("🥞", "workout.pancakes"), ("🎉", "party.popper.fill")] {
            #expect(WorkoutIconMatcher.match(name) == symbol)
            #expect(WorkoutSymbolEntry.search(name).flatMap(\.entries).contains { $0.id == symbol })
        }
        #expect(WorkoutIconMatcher.match("Bomb Run") == "burst.fill")
        #expect(WorkoutSymbolEntry.search("bomb").flatMap(\.entries).contains { $0.id == "burst.fill" })
        #expect(WorkoutIconMatcher.match("Fox Run") == "workout.fox")
        #expect(WorkoutIconMatcher.match("🦊") == "workout.fox")
        #expect(WorkoutIconMatcher.match("Crazy Day") == "sparkles")
    }
}
