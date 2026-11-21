//
//  RouteMap.swift
//  Wind Run
//

import MapKit
import SwiftUI

/// The run's route can be explored in place. The color control switches the overlay while the map
/// handles pans and pinches, and the expand button opens the full-screen map.
///
/// `routes` must not be empty; the run detail only shows the card when the run has a colored route.
struct RouteMapCard: View {
    let routes: [ColoredRoute]
    /// The screen the card is on, for the trace: "Run summary" or "Run detail".
    let screen: String

    @State private var selection: Int
    @State private var isShowingFullScreen = false
    @State private var keyHeight: CGFloat = 0

    init(routes: [ColoredRoute], screen: String = "Run detail") {
        self.routes = routes
        self.screen = screen
        var first = 0
        #if DEBUG
        // Launch with `-routeColoring cadence` (or `grade`) to open on that coloring, for screenshots.
        if let name = UserDefaults.standard.string(forKey: "routeColoring"),
           let index = routes.firstIndex(where: { $0.coloring.name.lowercased() == name.lowercased() }) {
            first = index
        }
        #endif
        _selection = State(initialValue: first)
    }

    var body: some View {
        RouteMapLayers(route: routes[selection])
            // Keeps the Maps logo, and the route, clear of the key.
            .safeAreaPadding(.bottom, keyHeight)
            .overlay(alignment: .topLeading) {
                RouteColorPicker(routes: routes, selection: $selection) {
                    RouteColoringName(routes: routes, selection: selection)
                }
                .padding(LayoutMetrics.compactSpacing)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    Trace.tap(screen, "Route map")
                    isShowingFullScreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.tint(.glassSurface.opacity(VisualOpacity.heavy)), in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open route map full screen")
                .padding(2)
            }
            .overlay(alignment: .bottom) {
                RouteColorKey(coloring: routes[selection].coloring)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .padding(LayoutMetrics.compactSpacing)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { keyHeight = $0 }
            }
            .frame(height: 280)
            .clipShape(.rect(cornerRadius: LayoutMetrics.cardCornerRadius))
            .onChange(of: selection) { _, selection in
                Trace.changed("Route map", "Color by", to: routes[selection].coloring.name)
            }
            .sensoryFeedback(.selection, trigger: selection)
            .chartFullScreenCover(isPresented: $isShowingFullScreen) {
                RouteMapFullScreen(routes: routes, selection: $selection)
            }
    }
}

/// The route map filling the screen, panning and zooming, with the key along the bottom. The map's own drags
/// pan it, so here a swipe on the key, or a tap, changes what the route is colored by.
private struct RouteMapFullScreen: View {
    @Environment(\.dismiss) private var dismiss

    let routes: [ColoredRoute]
    @Binding var selection: Int

    var body: some View {
        NavigationStack {
            RouteMapLayers(route: routes[selection])
                .ignoresSafeArea(edges: .bottom)
                .safeAreaBar(edge: .bottom) {
                    VStack(spacing: LayoutMetrics.compactSpacing) {
                        RouteColorPicker(routes: routes, selection: $selection) {
                            RouteColorKey(coloring: routes[selection].coloring)
                        }
                        ChartPageDots(count: routes.count, selection: selection)
                    }
                    .padding(.bottom, LayoutMetrics.compactSpacing)
                }
                .sensoryFeedback(.selection, trigger: selection)
                .navigationTitle(routes[selection].coloring.name)
                .traceScreen("Full screen map")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            Trace.tap("Full screen map", "Done")
                            dismiss()
                        }
                    }
                }
        }
        .allowsLandscape()
        .scrollEdgeEffectStyle(.soft, for: .all)
    }
}

/// The route drawn shade by shade over a thin dark edge, so every shade stands off the streets in light and dark.
private struct RouteMapLayers: View {
    let route: ColoredRoute

    var body: some View {
        Map(interactionModes: [.zoom, .pan]) {
            // One line under the whole route, a little wider than the shades on it. A single line, so it
            // doesn't darken where the shades meet.
            MapPolyline(coordinates: route.edge)
                .stroke(RouteShade.edge, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            ForEach(route.segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(RouteShade.color(level: segment.level, coloring: route.coloring), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        // Just the route and the streets, no shops or venues.
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

/// Keep paging gestures on the color control so every drag on the map can pan.
private struct RouteColorPicker<Label: View>: View {
    let routes: [ColoredRoute]
    @Binding var selection: Int
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button { step(1) } label: { label() }
            .buttonStyle(.plain)
            .highPriorityGesture(ChartPageSwipe.gesture(step))
            .accessibilityLabel("Route colors")
            .accessibilityValue(RouteColorKey.spokenValue(routes[selection].coloring))
            .accessibilityAdjustableAction { step(ChartPageSwipe.offset(for: $0)) }
            .disabled(routes.count < 2)
    }

    private func step(_ offset: Int) {
        selection = ChartPageSwipe.step(selection, by: offset, count: routes.count)
    }
}

/// "Pace" with a dot for each way the route can be colored, at the map's corner.
private struct RouteColoringName: View {
    let routes: [ColoredRoute]
    let selection: Int

    var body: some View {
        HStack(spacing: LayoutMetrics.compactSpacing) {
            Text(routes[selection].coloring.name)
                .font(.subheadline.weight(.semibold))
            ChartPageDots(count: routes.count, selection: selection)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(.glassSurface.opacity(VisualOpacity.heavy)), in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// "Slower", the shades from low to high, "Faster", in a capsule.
private struct RouteColorKey: View {
    let coloring: RouteColoring

    var body: some View {
        HStack(spacing: 10) {
            Text(coloring.ends.low)
            HStack(spacing: 2) {
                ForEach(0..<RouteColoring.levels, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(RouteShade.color(level: level, coloring: coloring))
                        .frame(width: 11, height: 14)
                }
            }
            Text(coloring.ends.high)
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(.glassSurface.opacity(VisualOpacity.heavy)), in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// "Colored by pace, slower to faster".
    static func spokenValue(_ coloring: RouteColoring) -> String {
        "Colored by \(coloring.name.lowercased()), \(coloring.ends.low.lowercased()) to \(coloring.ends.high.lowercased())"
    }
}

/// The route's shades, from the app's two colors: amber at the slow end and uphill, teal at the fast end and
/// downhill, through the green of the cat's eyes for pace and cadence and through grey for flat ground. Amber
/// against teal is the same blue–orange pair as easy and hard steps, which stays apart for red-green color
/// blindness, and the light-mode pace shades also darken toward teal. No red, which is kept for heart rate.
enum RouteShade {
    /// The thin dark line under the route.
    static let edge = Color.black.opacity(0.6)

    static func color(level: Int, coloring: RouteColoring) -> Color {
        let level = min(max(level, 0), RouteColoring.levels - 1)
        let pair = coloring == .grade ? grade[level] : speed[level]
        return Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
        })
    }

    /// How many shades each palette has, which must be `RouteColoring.levels`.
    static var paletteSizes: (speed: Int, grade: Int) { (speed.count, grade.count) }

    /// Slower to faster: amber, green, teal, blended in OKLab.
    private static let speed: [(light: UInt32, dark: UInt32)] = [
        (0xC77700, 0xE69F00),
        (0xB78119, 0xD6A929),
        (0xA78A27, 0xC5B23D),
        (0x949331, 0xB2BA4D),
        (0x7E9A3A, 0x9CC25A),
        (0x669054, 0x86BF7D),
        (0x4D8566, 0x6EBB98),
        (0x317974, 0x53B6B1),
        (0x006D80, 0x2EB0C7),
    ]

    /// Downhill to uphill: teal, grey for flat, amber, blended in OKLab.
    private static let grade: [(light: UInt32, dark: UInt32)] = [
        (0x006D80, 0x2EB0C7),
        (0x397887, 0x60B4C6),
        (0x58828E, 0x81B8C5),
        (0x748D94, 0x9EBBC4),
        (0x8E979B, 0xB8BEC2),
        (0x9E9181, 0xC5B8A2),
        (0xAD8965, 0xD1B07F),
        (0xBA8144, 0xDCA857),
        (0xC77700, 0xE69F00),
    ]
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
