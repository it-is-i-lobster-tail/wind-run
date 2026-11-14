//
//  RouteMap.swift
//  Wind Run
//

import MapKit
import SwiftUI

/// The run's route on a map, colored by pace, cadence or grade with a key along the bottom. Swipe sideways
/// to change what it's colored by; tap to open it full screen, where it pans and zooms.
struct RouteMapCard: View {
    let routes: [ColoredRoute]

    @State private var selection: Int
    @State private var isShowingFullScreen = false

    init(routes: [ColoredRoute]) {
        self.routes = routes
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
        RouteMapLayers(route: routes[selection], interactive: false)
            .overlay(alignment: .topLeading) {
                RouteColoringName(routes: routes, selection: selection)
                    .padding(LayoutMetrics.compactSpacing)
            }
            .overlay(alignment: .bottom) {
                RouteColorKey(coloring: routes[selection].coloring)
                    .padding(LayoutMetrics.compactSpacing)
            }
            .frame(height: 280)
            .clipShape(.rect(cornerRadius: LayoutMetrics.cardCornerRadius))
            .contentShape(.rect)
            // Alongside the page's scrolling, so an upward drag on the map still scrolls.
            .simultaneousGesture(RouteMapSwipe.gesture { selection = RouteMapSwipe.step(selection, by: $0, count: routes.count) })
            .onTapGesture { isShowingFullScreen = true }
            .sensoryFeedback(.selection, trigger: selection)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Route map")
            .accessibilityValue(RouteColorKey.spokenValue(routes[selection].coloring))
            .accessibilityHint(routes.count > 1 ? "Swipe up or down to color it another way. Double tap to open the map." : "Double tap to open the map.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                selection = RouteMapSwipe.step(selection, by: direction == .increment ? 1 : -1, count: routes.count)
            }
            .fullScreenCover(isPresented: $isShowingFullScreen) {
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
            RouteMapLayers(route: routes[selection], interactive: true)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: LayoutMetrics.compactSpacing) {
                        Button {
                            selection = RouteMapSwipe.step(selection, by: 1, count: routes.count)
                        } label: {
                            RouteColorKey(coloring: routes[selection].coloring)
                        }
                        .buttonStyle(.plain)
                        .disabled(routes.count < 2)
                        .highPriorityGesture(RouteMapSwipe.gesture { selection = RouteMapSwipe.step(selection, by: $0, count: routes.count) })
                        .accessibilityLabel("Route colors")
                        .accessibilityValue(RouteColorKey.spokenValue(routes[selection].coloring))
                        .accessibilityAdjustableAction { direction in
                            selection = RouteMapSwipe.step(selection, by: direction == .increment ? 1 : -1, count: routes.count)
                        }
                        RouteColoringDots(count: routes.count, selection: selection)
                    }
                    .padding(.bottom, LayoutMetrics.compactSpacing)
                }
                .sensoryFeedback(.selection, trigger: selection)
                .navigationTitle(routes[selection].coloring.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// The route drawn shade by shade over a thin dark edge, so every shade stands off the streets in light and dark.
private struct RouteMapLayers: View {
    let route: ColoredRoute
    let interactive: Bool

    var body: some View {
        Map(interactionModes: interactive ? [.zoom, .pan] : []) {
            // One line under the whole route, a little wider than the shades on it.
            ForEach(route.segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(RouteShade.edge, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            }
            ForEach(route.segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(RouteShade.color(level: segment.level, coloring: route.coloring), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        // Just the route and the streets, no shops or venues.
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
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
            RouteColoringDots(count: routes.count, selection: selection)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(.glassSurface.opacity(VisualOpacity.heavy)), in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// A dot for each way the route can be colored, the current one filled. Nothing when there's only one.
private struct RouteColoringDots: View {
    let count: Int
    let selection: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(index == selection ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
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

/// Changing what the route is colored by with a sideways swipe.
enum RouteMapSwipe {
    /// A drag that ends mostly sideways: 1 for a swipe to the left (the next coloring), -1 to the right.
    static func gesture(_ swiped: @escaping (Int) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 20).onEnded { value in
            let across = value.translation.width
            guard abs(across) >= 40, abs(across) > 1.5 * abs(value.translation.height) else { return }
            swiped(across < 0 ? 1 : -1)
        }
    }

    /// The coloring `offset` places on, wrapping round at either end.
    static func step(_ selection: Int, by offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((selection + offset) % count + count) % count
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
