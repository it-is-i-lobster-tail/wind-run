//
//  RunWeatherViews.swift
//  Wind Run
//
//  The weather pill on a run's map, the page it opens, and the one-time offer to turn Weather for Runs on.
//

import SwiftUI
import WeatherKit

/// "35°", the sky's symbol and the wind dial, in a capsule over the top corner of a run's map.
struct WeatherPill: View {
    let weather: RunWeather
    let unit: DistanceUnit

    var body: some View {
        HStack(spacing: 10) {
            Text(RunWeather.temperature(weather.temperature, unit: unit))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Image(systemName: weather.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title3)
            WindDial(fromDegrees: weather.windFrom, number: RunWeather.windNumber(weather.windSpeed, unit: unit))
        }
        .lineLimit(1)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(.glassSurface.opacity(VisualOpacity.heavy)), in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// The wind's speed in a ring, with a marker on the ring on the side the wind blew from, pointing the way it
/// blew. North is up, as on the map.
struct WindDial: View {
    let fromDegrees: Double
    let number: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary, lineWidth: 1.5)
            Text(number)
                .font(.system(size: size * 0.38, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 3)
            // The marker sits at the top of the ring, pointing in, and turns to where the wind came from.
            WindMarker()
                .fill(.primary)
                .frame(width: size * 0.3, height: size * 0.24)
                .offset(y: -size / 2 + size * 0.1)
                .rotationEffect(.degrees(fromDegrees))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A small triangle pointing down, toward the dial's middle.
private struct WindMarker: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// Everything kept about a run's weather, opened from the pill.
struct RunWeatherSheet: View {
    @Environment(\.dismiss) private var dismiss
    let weather: RunWeather
    let unit: DistanceUnit

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: weather.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(RunWeather.temperature(weather.temperature, unit: unit))
                                .font(.largeTitle.weight(.semibold))
                                .monospacedDigit()
                            Text(weather.condition)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        WindDial(fromDegrees: weather.windFrom, number: RunWeather.windNumber(weather.windSpeed, unit: unit), size: 52)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(weather.spoken(unit: unit))
                } footer: {
                    Text(when)
                }

                Section {
                    if let feelsLike = weather.feelsLike {
                        LabeledContent("Feels Like", value: RunWeather.temperature(feelsLike, unit: unit))
                    }
                    LabeledContent("Humidity", value: RunWeather.percent(weather.humidity))
                    LabeledContent("Cloud Cover", value: RunWeather.percent(weather.cloudCover))
                    LabeledContent("Wind", value: "\(RunWeather.wind(weather.windSpeed, unit: unit)) from \(RunWeather.compass(weather.windFrom))")
                    if let gust = weather.windGust, gust > weather.windSpeed {
                        LabeledContent("Gusts", value: RunWeather.wind(gust, unit: unit))
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("For the area within about 4 km (2.5 mi) of where the run started. Only that rounded spot and the time were sent to Apple Weather.")
                        AppleWeatherCredit()
                    }
                }
            }
            .navigationTitle("Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Trace.tap("Run weather", "Done")
                        dismiss()
                    }
                }
            }
        }
        .traceScreen("Run weather")
    }

    /// "At the finish" or "Around 7 AM".
    private var when: String {
        weather.isCurrent ? "At the finish" : "Around \(weather.date.formatted(date: .omitted, time: .shortened))"
    }
}

/// The Apple Weather mark and the link to its other data sources, which WeatherKit asks apps to show beside
/// its weather. The mark comes from Apple, so it shows the words until it loads.
struct AppleWeatherCredit: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherAttribution?

    var body: some View {
        HStack(spacing: 8) {
            if let attribution {
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(attribution.serviceName)
                }
                .frame(height: 12)
                .accessibilityLabel(attribution.serviceName)
                Link("Other data sources", destination: attribution.legalPageURL)
            } else {
                Text("Apple Weather")
            }
        }
        .font(.footnote)
        .task {
            guard attribution == nil else { return }
            attribution = try? await WeatherService.shared.attribution
        }
    }
}

/// Offers Weather for Runs once, on a finished run's page, until the runner answers.
struct RunWeatherOffer: View {
    let screen: String
    @AppStorage(RunWeatherFetcher.enabledKey) private var isEnabled = false
    @AppStorage(RunWeatherFetcher.offerAnsweredKey) private var isAnswered = false

    var body: some View {
        if !isEnabled && !isAnswered {
            VStack(alignment: .leading, spacing: 12) {
                Label("Add Weather to Runs?", systemImage: "cloud.sun")
                    .font(.headline)
                Text("Wind Run can ask Apple Weather for the temperature, sky, wind and humidity on each run. Only a spot rounded to about 5 km and the time are sent, never your route.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Not Now") {
                        Trace.tap(screen, "Weather offer: Not Now")
                        isAnswered = true
                    }
                    .buttonStyle(.glass)
                    Spacer()
                    Button("Add Weather") {
                        Trace.tap(screen, "Weather offer: Add Weather")
                        isAnswered = true
                        isEnabled = true
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .windRunGlassCard()
        }
    }
}
