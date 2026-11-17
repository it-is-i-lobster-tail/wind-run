//
//  CoachHomeView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// The Coach section: the terms first if they haven't been accepted, then the current plan,
/// or the way to start one.
struct CoachHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [CoachPlan]

    @State private var termsAccepted = TermsAcceptance.isCurrent()
    /// Opens setup again after an unreadable plan is stopped.
    @State private var setUpAgain = false
    @State private var confirmsSetUpAgain = false

    private var currentPlan: CoachPlan? { plans.active }

    /// A plan that reached its event in the last two weeks, for a word about it on the start screen.
    private var recentlyFinished: CoachPlan? {
        let since = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        return plans
            .filter { $0.status == .complete && ($0.eventDate ?? .distantPast) >= since }
            .max { ($0.eventDate ?? .distantPast) < ($1.eventDate ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !termsAccepted {
                    TermsView {
                        TermsAcceptance.accept()
                        termsAccepted = true
                    }
                } else if let currentPlan {
                    switch BuildService(context: modelContext).problem(with: currentPlan) {
                    case nil:
                        BuildPlanView(plan: currentPlan)
                    case .loading:
                        LoadingPlanView()
                    case .newer:
                        NewerPlanView()
                    case .unreadable:
                        UnreadablePlanView {
                            Trace.tap("Coach", "Set it up again")
                            confirmsSetUpAgain = true
                        }
                    }
                } else {
                    CoachStartView(startWith: $setUpAgain, finished: recentlyFinished)
                }
            }
            .clearsFloatingBar()
            .navigationTitle("Coach")
            .traceScreen("Coach")
            .confirmationDialog("Set up a new plan?", isPresented: $confirmsSetUpAgain, titleVisibility: .visible) {
                Button("Set up a new plan") {
                    Trace.tap("Coach", "Set up a new plan?: Set up")
                    guard let currentPlan else { return }
                    setUpAgain = true
                    BuildService(context: modelContext).retireUnreadable(currentPlan)
                }
                Button("Not now", role: .cancel) {
                    Trace.tap("Coach", "Set up a new plan?: Not now")
                }
            } message: {
                Text("The plan that can't be opened stops on all your devices. Your runs stay in your history.")
            }
        }
    }
}

/// A plan whose weeks haven't come over from iCloud yet: it shows once they arrive.
private struct LoadingPlanView: View {
    var body: some View {
        ContentUnavailableView {
            ProgressView()
                .controlSize(.large)
        } description: {
            Text("Loading your plan from iCloud. It shows here once it arrives from your other devices.")
        }
        .onAppear { Trace.log(.coach, "Plan waiting for iCloud") }
    }
}

/// A plan a newer Wind Run saved on another device, which this version can't open without losing some of it.
private struct NewerPlanView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Update Wind Run", systemImage: "arrow.down.app")
        } description: {
            Text("Your plan was saved by a newer version of Wind Run on another device. Update Wind Run on this device to open it.")
        }
        .onAppear { Trace.log(.coach, "Plan from a newer version") }
    }
}

/// A plan made by an earlier version of the coach, whose state this version can't read.
private struct UnreadablePlanView: View {
    let setUpAgain: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Plan can't be opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Your plan was made by an earlier version of the coach and can't be opened. Set it up again.")
        } actions: {
            Button("Set it up again", action: setUpAgain)
                .prominentAccentButton()
        }
    }
}

#Preview("Coach - No plan") {
    CoachHomeView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
