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
    /// A run saved here, or sent from the watch, counts toward the week straight away. Only finished runs, counted
    /// without reading each one, so the saves during a run stay cheap.
    @Query(filter: #Predicate<Run> { $0.endDateValue != nil }) private var finishedRuns: [Run]

    let plan: CoachPlan?

    func body(content: Content) -> some View {
        content
            .task(id: plan?.persistentModelID) { refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh() }
            // A trip to another time zone moves the plan's days there.
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                NSTimeZone.resetSystemTimeZone()
                refresh()
            }
            .onChange(of: finishedRuns.count) { refresh() }
    }

    private func refresh() {
        guard let plan else { return }
        BuildService(context: modelContext).refresh(plan)
    }
}
