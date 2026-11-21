import Charts
import SwiftUI
import UIKit

/// The chart supplies its scale and ticks for the visible interval. Inline and expanded charts use the
/// same plot-local gestures, whether their horizontal axis measures seconds, dates, distance, or reps.
struct ZoomableChart<Content: View>: View {
    let domain: ClosedRange<Double>
    let minimumSpan: Double
    var plotInset: CGFloat = 0
    @ViewBuilder let chart: (ClosedRange<Double>) -> Content

    @Environment(\.expandRunChart) private var expand
    @State private var window: ClosedRange<Double>?
    @State private var pinchStart: ClosedRange<Double>?
    @State private var dragStart: ClosedRange<Double>?
    /// A finger held on the plot, then slid, moves the measuring line instead of panning or paging.
    @GestureState private var measuring = false

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
                            .simultaneousGesture(pinch(width: plot.width, visible: visible))
                            .simultaneousGesture(touch(proxy: proxy, zoomed: visible != domain))
                            .frame(width: plot.width, height: plot.height)
                            .position(x: plot.midX, y: plot.midY)
                            .accessibilityHidden(true)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: measuring) { _, isMeasuring in isMeasuring }
            .preference(key: ChartZoomed.self, value: visible != domain || measuring)
            .onChange(of: domain) { window = nil; pinchStart = nil; dragStart = nil }
            #if DEBUG
            .onAppear {
                if window == nil, let zoom = RunDetailDemo.zoom {
                    window = ChartWindow.zoom(domain, by: zoom, anchor: 0.5, within: domain, minimumSpan: minimumSpan)
                }
            }
            #endif
    }

    private func pinch(width: CGFloat, visible: ClosedRange<Double>) -> some Gesture {
        let scaleWidth = max(1, width - 2 * plotInset)
        return MagnifyGesture()
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
    }

    /// Touch and hold, then slide, to measure. Lift sooner and it's a tap: it opens an unzoomed card, and
    /// otherwise puts the measuring line where it landed.
    private func touch(proxy: ChartProxy, zoomed: Bool) -> some Gesture {
        let measure = LongPressGesture(minimumDuration: ChartTouch.holdToMeasure)
            .sequenced(before: DragGesture(minimumDistance: 0))
        return measure.exclusively(before: tap(zoomed: zoomed))
            .updating($measuring) { value, isMeasuring, _ in
                if case .first(.second(true, _)) = value { isMeasuring = true }
            }
            .onChanged { value in
                if case .first(.second(true, let drag?)) = value {
                    proxy.selectXValue(at: drag.location.x)
                }
            }
            .onEnded { value in
                switch value {
                case .first:
                    Trace.tap("Chart", "Measure")
                case .second(.showWholeRun):
                    Trace.tap("Chart", "Show whole run")
                    withAnimation { window = nil }
                case .second(.at(let point)):
                    if !zoomed, let expand {
                        expand.wrappedValue = true
                    } else {
                        proxy.selectXValue(at: point.x)
                    }
                }
            }
    }

    /// A double tap only does something once zoomed in, to show the whole run again. Telling one apart holds
    /// every single tap back about a third of a second, so an unzoomed chart answers a single tap at once.
    private func tap(zoomed: Bool) -> AnyGesture<ChartTouch.Tap> {
        guard zoomed else {
            return AnyGesture(SpatialTapGesture().map { ChartTouch.Tap.at($0.location) })
        }
        return AnyGesture(
            SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture()).map { result -> ChartTouch.Tap in
                switch result {
                case .first: .showWholeRun
                case .second(let tap): .at(tap.location)
                }
            }
        )
    }

    private func pan(width: CGFloat, visible: ClosedRange<Double>) -> HorizontalChartDrag {
        HorizontalChartDrag(enabled: visible != domain) { state, translation in
            switch state {
            case .began:
                dragStart = visible
            case .changed, .ended:
                // A slide that started as a measurement never pans, even after the line is let go.
                if measuring { dragStart = nil }
                guard pinchStart == nil, let original = dragStart else { return }
                let span = original.upperBound - original.lowerBound
                let shift = translation.width / max(1, width - 2 * plotInset) * span
                window = ChartWindow.clamped(start: original.lowerBound - shift, span: span, within: domain)
                if state == .ended { dragStart = nil }
            default:
                dragStart = nil
            }
        }
    }
}

/// Let the surrounding scroll view handle vertical drags starting inside a plot.
private struct HorizontalChartDrag: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let update: (UIGestureRecognizer.State, CGSize) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.isEnabled = enabled
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        pan.isEnabled = enabled
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

enum ChartTouch {
    /// How long a finger rests on a plot before sliding it measures. Shorter than the system's long press, so
    /// it doesn't feel slow, and long enough that a quick swipe still scrolls or pans.
    static let holdToMeasure: Double = 0.25

    enum Tap: Equatable {
        case showWholeRun
        case at(CGPoint)
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
