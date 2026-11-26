//
//  LiveRunView.swift
//  Wind Run
//

import SwiftUI

/// The run under way on the other device: its time, distance, pace and heart rate, with Pause, Resume and
/// Finish passed back to it.
struct LiveRunView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    let status: LiveRunStatus
    let receivedAt: Date
    var link: LiveRunLink = .shared
    @State private var confirmsFinish = false

    private var deviceName: String {
        status.device == .watch ? "Apple Watch" : "iPhone"
    }

    private var deviceSymbol: String {
        status.device == .watch ? "applewatch" : "iphone"
    }

    var body: some View {
        TimelineView(.periodic(from: receivedAt, by: 1)) { context in
            content(at: context.date)
        }
        .confirmationDialog("Finish this \(status.sport.noun)?", isPresented: $confirmsFinish, titleVisibility: .visible) {
            Button("Finish \(status.sport.noun.capitalized)") {
                Trace.tap("Live run", "Finish confirmed")
                link.send(.finish)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's saved on your \(deviceName).")
        }
    }

    private func content(at date: Date) -> some View {
        let quiet = link.isQuiet(at: date)
        return ScrollView {
            VStack(spacing: spacing) {
                Label(caption(quiet: quiet), systemImage: deviceSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(quiet || status.state == .paused ? Color.secondary : Color.accentColor)
                    .accessibilityAddTraits(.isHeader)

                Text(RunFormat.duration(status.elapsed(at: date, receivedAt: receivedAt)))
                    .font(timeFont)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Time \(RunFormat.duration(status.elapsed(at: date, receivedAt: receivedAt)))")

                Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        reading("Distance", RunFormat.distance(status.meters, unit: unit))
                        reading("Pace", RunFormat.pace(status.currentPace ?? status.averagePace, unit: unit))
                    }
                    if status.beatsPerMinute != nil {
                        GridRow {
                            reading("Heart Rate", RunFormat.heartRate(status.beatsPerMinute))
                                .gridCellColumns(2)
                        }
                    }
                }

                controls
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
    }

    private func caption(quiet: Bool) -> String {
        if quiet { return "Waiting for \(deviceName)…" }
        let what = status.sport.noun.capitalized
        return status.state == .paused ? "\(what) paused on \(deviceName)" : "\(what) on \(deviceName)"
    }

    private func reading(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(readingFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var controls: some View {
        let paused = status.state == .paused
        VStack(spacing: 8) {
            Button(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill") {
                Trace.tap("Live run", paused ? "Resume" : "Pause")
                link.send(paused ? .resume : .pause)
            }
            .tint(.accentColor)
            .foregroundStyle(.onAccent)
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)

            Button("Finish", systemImage: "flag.checkered") {
                Trace.tap("Live run", "Finish")
                confirmsFinish = true
            }
            .buttonStyle(.bordered)

            Button("Hide") {
                link.hideRemote()
            }
            .font(.footnote)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityHint("Stops showing this \(status.sport.noun) here. It carries on on your \(deviceName).")
        }
        #if os(iOS)
        .controlSize(.large)
        .padding(.top, 24)
        #endif
    }

    private var spacing: CGFloat {
        #if os(watchOS)
        6
        #else
        20
        #endif
    }

    private var timeFont: Font {
        #if os(watchOS)
        .system(.title, design: .rounded).weight(.semibold)
        #else
        .system(size: 72, weight: .semibold, design: .rounded)
        #endif
    }

    private var readingFont: Font {
        #if os(watchOS)
        .system(.headline, design: .rounded)
        #else
        .system(.title, design: .rounded).weight(.semibold)
        #endif
    }
}

extension View {
    /// Shows the run under way on the other device over this screen, while there is one.
    func showsLiveRunFromOtherDevice(_ link: LiveRunLink = .shared) -> some View {
        modifier(LiveRunCover(link: link))
    }
}

private struct LiveRunCover: ViewModifier {
    let link: LiveRunLink

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(
            get: { link.remote != nil },
            set: { if !$0 { link.hideRemote() } }
        )) {
            if let status = link.remote, let receivedAt = link.receivedAt {
                LiveRunView(status: status, receivedAt: receivedAt, link: link)
                    #if os(iOS)
                    .interactiveDismissDisabled()
                    #endif
            }
        }
    }
}
