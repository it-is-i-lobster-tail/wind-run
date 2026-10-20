//
//  CoachRouter.swift
//  Wind Run
//

import Observation
import SwiftData
import SwiftUI

/// Which coach screen is showing over a page, and the one to open after it closes, such as
/// Report injury after a check-in.
@Observable
final class CoachRouter {
    var sheet: CoachSheet?
    @ObservationIgnored private var nextSheet: CoachSheet?

    /// Opens a coach screen, or queues it when another is showing and closes that one first.
    func open(_ next: CoachSheet) {
        if sheet == nil {
            sheet = next
        } else {
            nextSheet = next
            sheet = nil
        }
    }

    fileprivate func showNextSheet() {
        guard let next = nextSheet else { return }
        nextSheet = nil
        sheet = next
    }
}

extension View {
    /// Shows the coach screens the router opens, for the runner's current plan.
    func coachSheets(_ router: CoachRouter, plan: CoachPlan?) -> some View {
        modifier(CoachSheets(router: router, plan: plan))
    }
}

private struct CoachSheets: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(CoachInbox.self) private var inbox

    @Bindable var router: CoachRouter
    let plan: CoachPlan?

    func body(content: Content) -> some View {
        content
            .sheet(item: $router.sheet, onDismiss: router.showNextSheet) { sheet in
                if let plan {
                    screen(for: sheet, actions: CoachActions(context: modelContext, plan: plan, inbox: inbox))
                }
            }
    }

    @ViewBuilder
    private func screen(for sheet: CoachSheet, actions: CoachActions) -> some View {
        switch sheet {
        case .runCheckIn(let runID):
            if let run = actions.run(withID: runID) {
                RunCheckInView(run: run, actions: actions) {
                    router.open(.reportInjury(origin: .runSummary, runID: runID))
                }
            } else {
                ContentUnavailableView("Run not found", systemImage: "figure.run")
            }
        case .weeklyCheckIn(let weekIndex):
            WeeklyCheckInView(weekIndex: weekIndex, actions: actions) { kind in
                router.open(.lifeHappens(kind))
            }
        case .morningCheck(let runID):
            MorningCheckView(actions: actions) {
                router.open(.reportInjury(origin: .morningCheck, runID: runID))
            }
        case .reportInjury(let origin, let runID):
            ReportInjuryView(origin: origin, runID: runID, actions: actions) { reportID in
                router.open(.recoveryPlan(reportID: reportID))
            }
        case .recoveryPlan(let reportID):
            RecoveryPlanEditor(reportID: reportID, actions: actions)
        case .returnPlan(let reportID):
            ReturnEditor(reportID: reportID, actions: actions)
        case .lifeHappens(let kind):
            LifeHappensView(kind: kind, actions: actions) {
                router.open(.reportInjury(origin: .lifeHappens, runID: nil))
            }
        case .settings:
            CoachPlanSettingsView(actions: actions, editRecovery: router.open)
        }
    }
}
