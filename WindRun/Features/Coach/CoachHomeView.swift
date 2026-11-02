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
                    if BuildService(context: modelContext).hasUnreadableState(currentPlan) {
                        UnreadablePlanView {
                            setUpAgain = true
                            BuildService(context: modelContext).retireUnreadable(currentPlan)
                        }
                    } else {
                        BuildPlanView(plan: currentPlan)
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
