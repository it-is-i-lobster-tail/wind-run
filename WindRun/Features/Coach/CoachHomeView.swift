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
    @Environment(\.scenePhase) private var scenePhase
    @Query private var plans: [CoachPlan]

    @Environment(CoachInbox.self) private var inbox
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
        // The coach catches up at app open and when the day changes.
        .task(id: currentPlan?.persistentModelID) { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh() }
    }

    private func refresh() {
        guard termsAccepted, let currentPlan else { return }
        if let update = CoachService(context: modelContext).refresh(currentPlan) {
            inbox.receive(update)
        }
    }
}

#Preview("Coach - No plan") {
    CoachHomeView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
        .environment(CoachInbox())
}
