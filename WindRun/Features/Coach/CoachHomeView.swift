//
//  CoachHomeView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// The Coach section: the terms first if they haven't been accepted, then the current plan,
/// or the way to start one.
struct CoachHomeView: View {
    @Query private var plans: [CoachPlan]
    @State private var termsAccepted = TermsAcceptance.isCurrent()

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
                    CoachPlanView(plan: currentPlan)
                } else {
                    CoachStartView()
                }
            }
            .clearsFloatingBar()
            .navigationTitle("Coach")
        }
    }
}

#Preview("Coach - No plan") {
    CoachHomeView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
