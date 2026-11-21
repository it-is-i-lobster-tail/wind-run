import Charts
import SwiftUI
import UIKit

/// The chart supplies its scale and ticks for the visible interval. Inline and expanded charts use the
/// same plot-local gestures, whether their horizontal axis measures seconds, dates, distance, or reps.
struct ZoomableChart<Content: View>: View {
    let domain: ClosedRange<Double>
    let minimumSpan: Double
    var plotInset: CGFloat = 0
    @Environment(MetricChartPages.self) private var pages: MetricChartPages?
    @ViewBuilder let chart: (ClosedRange<Double>) -> Content

    @Environment(\.expandRunChart) private var expand
    @State private var window: ClosedRange<Double>?
    @State private var pinchStart: ClosedRange<Double>?
    @State private var dragStart: ClosedRange<Double>?

    var body: some View {
        let visible = window ?? domain
        chart(visible)
            .chartPlotStyle { $0.clipped() }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let frame = proxy.plotFrame {
                        let plot = geometry[frame]
                        Rectangle().fill(.clear)
                            .contentShape(.rect)
                            .gesture(pan(width: plot.width, visible: visible))
                            .simultaneousGesture(gestures(proxy: proxy, width: plot.width, visible: visible))
                            .frame(width: plot.width, height: plot.height)
                            .position(x: plot.midX, y: plot.midY)
                            .accessibilityHidden(true)
                    }
                }
            }
            .onChange(of: domain) { window = nil; pinchStart = nil; dragStart = nil }
            #if DEBUG
            .onAppear {
                if window == nil, let zoom = RunDetailDemo.zoom {
                    window = ChartWindow.zoom(domain, by: zoom, anchor: 0.5, within: domain, minimumSpan: minimumSpan)
                }
            }
            #endif
    }

    private func gestures(proxy: ChartProxy, width: CGFloat, visible: ClosedRange<Double>) -> some Gesture {
        let scaleWidth = max(1, width - 2 * plotInset)
        let pinch = MagnifyGesture()
            .onChanged { value in
                let original = pinchStart ?? visible
                pinchStart = original
                dragStart = nil
                let anchor = (value.startAnchor.x * width - plotInset) / scaleWidth
                window = ChartWindow.zoom(original, by: value.magnification, anchor: anchor,
                                          within: domain, minimumSpan: minimumSpan)
            }
            .onEnded { _ in
                pinchStart = nil
                if let window {
                    let factor = (domain.upperBound - domain.lowerBound) / (window.upperBound - window.lowerBound)
                    Trace.changed("Chart", "Zoom", to: (factor * 10).rounded() / 10)
                }
            }
        let tap = SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture())
            .onEnded { result in
                switch result {
                case .first:
                    Trace.tap("Chart", "Show whole run")
                    withAnimation { window = nil }
                case .second(let point):
                    if visible == domain, let expand {
                        expand.wrappedValue = true
                    } else {
                        proxy.selectXValue(at: point.location.x)
                    }
                }
            }
        return pinch.simultaneously(with: tap)
    }

    private func pan(width: CGFloat, visible: ClosedRange<Double>) -> HorizontalChartDrag {
        HorizontalChartDrag { state, translation in
            switch state {
            case .began:
                dragStart = visible
            case .changed, .ended:
                guard pinchStart == nil, let original = dragStart else { return }
                if original != domain {
                    let span = original.upperBound - original.lowerBound
                    let shift = translation.width / max(1, width - 2 * plotInset) * span
                    window = ChartWindow.clamped(start: original.lowerBound - shift, span: span, within: domain)
                } else if state == .ended, let offset = ChartPageSwipe.offset(for: translation) {
                    pages?.advance(offset)
                }
                if state == .ended { dragStart = nil }
            default:
                dragStart = nil
            }
        }
    }
}

/// Let the surrounding scroll view handle vertical drags starting inside a plot.
private struct HorizontalChartDrag: UIGestureRecognizerRepresentable {
    let update: (UIGestureRecognizer.State, CGSize) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let translation = pan.translation(in: pan.view)
        update(pan.state, CGSize(width: translation.x, height: translation.y))
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}

enum ChartWindow {
    static func zoom(_ original: ClosedRange<Double>, by scale: Double, anchor: Double,
                     within domain: ClosedRange<Double>, minimumSpan: Double) -> ClosedRange<Double> {
        guard scale.isFinite, scale > 0 else { return original }
        let originalSpan = original.upperBound - original.lowerBound
        let span = min(domain.upperBound - domain.lowerBound, max(minimumSpan, originalSpan / scale))
        let fraction = min(1, max(0, anchor))
        return clamped(start: original.lowerBound + fraction * (originalSpan - span), span: span, within: domain)
    }

    static func clamped(start: Double, span: Double, within domain: ClosedRange<Double>) -> ClosedRange<Double> {
        if span >= domain.upperBound - domain.lowerBound { return domain }
        let lower = min(max(start, domain.lowerBound), domain.upperBound - span)
        return lower...min(domain.upperBound, lower + span)
    }
}
