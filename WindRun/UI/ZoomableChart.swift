import Charts
import SwiftUI

/// The chart supplies its scale and ticks for the visible interval. All full-screen charts use the
/// same plot-local gestures, whether their horizontal axis measures seconds, dates, distance, or reps.
struct ZoomableChart<Content: View>: View {
    let domain: ClosedRange<Double>
    let minimumSpan: Double
    var plotInset: CGFloat = 0
    @ViewBuilder let chart: (ClosedRange<Double>) -> Content

    @Environment(\.runChartZooms) private var interactive
    @State private var window: ClosedRange<Double>?
    @State private var pinchStart: ClosedRange<Double>?
    @State private var dragStart: ClosedRange<Double>?

    var body: some View {
        if interactive {
            let visible = window ?? domain
            chart(visible)
                .chartPlotStyle { $0.clipped() }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let frame = proxy.plotFrame {
                            let plot = geometry[frame]
                            Rectangle().fill(.clear)
                                .contentShape(.rect)
                                .gesture(gestures(proxy: proxy, width: plot.width, visible: visible))
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
        } else {
            chart(domain)
        }
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
                    Trace.changed("Full screen chart", "Zoom", to: (factor * 10).rounded() / 10)
                }
            }
        let pan = DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard pinchStart == nil, visible != domain else { return }
                let original = dragStart ?? visible
                dragStart = original
                let span = original.upperBound - original.lowerBound
                window = ChartWindow.clamped(start: original.lowerBound - value.translation.width / scaleWidth * span,
                                             span: span, within: domain)
            }
            .onEnded { _ in dragStart = nil }
        let tap = SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture())
            .onEnded { result in
                switch result {
                case .first:
                    Trace.tap("Full screen chart", "Show whole run")
                    withAnimation { window = nil }
                case .second(let point):
                    proxy.selectXValue(at: point.location.x)
                }
            }
        return pinch.simultaneously(with: pan).simultaneously(with: tap)
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
