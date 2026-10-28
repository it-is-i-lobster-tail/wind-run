//
//  CoachRefresh.swift
//  Wind Run
//

import SwiftData
import SwiftUI

extension View {
    /// Lets the coach catch up at app open, when the app comes back and when the day changes, so
    /// today's plan is current on every screen that shows it. Pass nil before the terms are accepted.
    func refreshesCoach(_ plan: CoachPlan?) -> some View {
        modifier(CoachRefresh(plan: plan))
    }
}

private struct CoachRefresh: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CoachInbox.self) private var inbox
    /// A run saved here, or sent from the watch, counts toward the week straight away.
    @Query private var runs: [Run]

    let plan: CoachPlan?

    func body(content: Content) -> some View {
        content
            .task(id: plan?.persistentModelID) { refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh() }
            .onChange(of: runs.lazy.filter { $0.status == .complete }.count) {
                if plan?.isBuild == true { refresh() }
            }
    }

    private func refresh() {
        guard let plan else { return }
        if plan.isBuild {
            BuildService(context: modelContext).refresh(plan)
            return
        }
        guard let update = CoachService(context: modelContext).refresh(plan) else { return }
        inbox.receive(update)
    }
}
