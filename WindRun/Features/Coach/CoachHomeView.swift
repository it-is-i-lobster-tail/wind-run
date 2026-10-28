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
    /// The goal to set up again after an unreadable plan is stopped.
    @State private var setUpAgain: CoachGoal?

    private var currentPlan: CoachPlan? { plans.active }

    var body: some View {
        NavigationStack {
            Group {
                if !termsAccepted {
                    TermsView {
                        TermsAcceptance.accept()
                        termsAccepted = true
                    }
                } else if let currentPlan {
                    if currentPlan.isBuild, !BuildService(context: modelContext).hasUnreadableState(currentPlan) {
                        BuildPlanView(plan: currentPlan)
                    } else if currentPlan.isBuild {
                        UnreadablePlanView {
                            setUpAgain = .buildDistance
                            BuildService(context: modelContext).retireUnreadable(currentPlan)
                        }
                    } else if CoachService(context: modelContext).hasUnreadableState(currentPlan) {
                        UnreadablePlanView {
                            setUpAgain = CoachGoal(rawValue: currentPlan.flavor) ?? .buildDistance
                            CoachService(context: modelContext).retireUnreadable(currentPlan)
                        }
                    } else {
                        CoachPlanView(plan: currentPlan)
                    }
                } else {
                    CoachStartView(startWith: $setUpAgain)
                }
            }
            .clearsFloatingBar()
            .navigationTitle("Coach")
        }
    }
}

/// A plan saved by an earlier test build whose state this version can't read.
private struct UnreadablePlanView: View {
    let setUpAgain: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Plan can't be opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Your plan was saved by an earlier test version and can't be opened. Set it up again.")
        } actions: {
            Button("Set it up again", action: setUpAgain)
                .prominentAccentButton()
        }
    }
}

#Preview("Coach - No plan") {
    CoachHomeView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
        .environment(CoachInbox())
}
