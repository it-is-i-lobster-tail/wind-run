import SwiftUI
import UIKit

/// Capture the live summary in viewport-sized slices so the current map and chart pages
/// are included alongside SwiftUI content below the fold.
@MainActor
final class SummaryImageCapture {
    weak var marker: UIView?

    func image(title: String) -> UIImage? {
        var ancestor = marker?.superview
        while ancestor != nil && !(ancestor is UIScrollView) { ancestor = ancestor?.superview }
        guard let scroll = ancestor as? UIScrollView, let window = scroll.window else { return nil }
        let width = scroll.bounds.width
        let height = scroll.contentSize.height
        let page = scroll.bounds.height
        guard width > 0, height > 0, page > 0 else { return nil }
        let original = scroll.contentOffset
        let indicator = scroll.showsVerticalScrollIndicator
        let topHidden = scroll.topEdgeEffect.isHidden
        let bottomHidden = scroll.bottomEdgeEffect.isHidden
        defer {
            scroll.setContentOffset(original, animated: false)
            scroll.showsVerticalScrollIndicator = indicator
            scroll.topEdgeEffect.isHidden = topHidden
            scroll.bottomEdgeEffect.isHidden = bottomHidden
        }
        scroll.topEdgeEffect.isHidden = true
        scroll.bottomEdgeEffect.isHidden = true
        scroll.showsVerticalScrollIndicator = false
        let header: CGFloat = 52
        let size = CGSize(width: width, height: height + header)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = min(window.screen.scale, sqrt(12_000_000 / (size.width * size.height)))
        var complete = true
        let result = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            scroll.traitCollection.performAsCurrent {
                UIColor.systemBackground.setFill()
                renderer.fill(CGRect(origin: .zero, size: size))
                (title as NSString).draw(at: CGPoint(x: 16, y: 16), withAttributes: [
                    .font: UIFont.preferredFont(forTextStyle: .headline), .foregroundColor: UIColor.label
                ])
                // Sample the interior so bars outside the scroll view never tint a tile edge.
                let margin = min(page / 4, max(80, scroll.adjustedContentInset.top))
                let step = page - 2 * margin
                let tileFormat = UIGraphicsImageRendererFormat()
                tileFormat.scale = format.scale
                let viewport = CGRect(origin: .zero, size: scroll.bounds.size)
                let tileRenderer = UIGraphicsImageRenderer(size: viewport.size, format: tileFormat)
                var y: CGFloat = 0
                while y < height {
                    let offset = y - margin
                    scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                    scroll.layoutIfNeeded()
                    let context = renderer.cgContext
                    context.saveGState()
                    context.clip(to: CGRect(x: 0, y: header + y, width: width, height: min(step, height - y)))
                    let rect = CGRect(x: 0, y: header + scroll.contentOffset.y, width: width, height: page)
                    let tile = tileRenderer.image { _ in
                        if !scroll.drawHierarchy(in: viewport, afterScreenUpdates: true) { complete = false }
                    }
                    tile.draw(in: rect)
                    context.restoreGState()
                    y += step
                }
            }
        }
        return complete ? result : nil
    }
}

struct SummaryCaptureMarker: UIViewRepresentable {
    let capture: SummaryImageCapture
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        capture.marker = view
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

final class SharedSummaryImage: Identifiable {
    let url: URL
    init?(_ image: UIImage) {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("Workout-\(UUID().uuidString).png")
        guard let data = image.pngData(), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}
