import SwiftUI
import Testing
@testable import WindRun

@MainActor
struct WorkoutGlyphTests {
    /// Compare painted bounds at the same font size, including transparent symbol margins.
    private func paintedSize(_ symbol: String, at points: CGFloat) throws -> CGSize {
        let glyph = WorkoutGlyph(value: symbol).font(.system(size: points)).foregroundStyle(.black).fixedSize().padding(4)
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = 3
        let image = try #require(renderer.cgImage)
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
        for points: CGFloat in [17, 28] {
            let native = try paintedSize("bird.fill", at: points)
            for id in WorkoutIcon.identifiers.filter({ $0.hasPrefix("workout.") }).sorted() {
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
            #expect(WorkoutIconMatcher.match(name) { _, _ in .infinity } == symbol)
            #expect(WorkoutSymbolEntry.search(name).flatMap(\.entries).contains { $0.id == symbol })
        }
        #expect(WorkoutIconMatcher.match("Bomb Run") { _, _ in .infinity } == "burst.fill")
        #expect(WorkoutSymbolEntry.search("bomb").flatMap(\.entries).contains { $0.id == "burst.fill" })
        #expect(WorkoutIconMatcher.match("Fox Run") { _, _ in .infinity } == "workout.fox")
        #expect(WorkoutIconMatcher.match("🦊") { _, _ in .infinity } == "workout.fox")
        #expect(WorkoutIconMatcher.match("Crazy Day") { _, _ in .infinity } == "sparkles")
    }
}
