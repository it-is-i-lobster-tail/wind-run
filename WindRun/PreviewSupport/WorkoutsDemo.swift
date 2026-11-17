//
//  WorkoutsDemo.swift
//  Wind Run
//

#if DEBUG
import Foundation

/// Opens the Workout page on one of its pages, with the sample runs, for simulator screenshots, which can't
/// tap. Launch with `-workoutsDemo PAGE`, where PAGE is list, distance, time, ready, timed-ready, free-ready,
/// saved-ready, coach-ready, new (New Workout), edit (Edit Workout on the first saved workout), or
/// edit-warmup, edit-main or edit-cooldown for that part's page pushed in Edit Workout, or edit-pace for the
/// Target Pace page on the first workout with a pace, edit-bottom for Edit Workout scrolled to its Display row,
/// edit-pick-display for its display picker, or displays for the Displays list. Add "-miles" to an edit page, such as edit-miles or
/// edit-pace-miles, for the workout switched to miles with the pill. Debug builds only.
enum WorkoutsDemo {
    static var page: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-workoutsDemo") else { return nil }
        return arguments.indices.contains(index + 1) ? arguments[index + 1] : "list"
    }

    /// The Edit Display preview `-workoutsDemo edit-display-watch` or `edit-display-lock` opens on.
    static var editDisplayDevice: EditDisplayView.PreviewDevice {
        switch page {
        case "edit-display-watch": .watch
        case "edit-display-lock": .lockScreen
        default: .iPhone
        }
    }

    /// The builder to open for `page`, and the part's page pushed in it, or nil when the page isn't the builder.
    /// True for `edit-bottom`, Edit Workout scrolled down to its Display row.
    static var scrollsToDisplay: Bool { page == "edit-bottom" }

    /// True for an edit page with "-miles", which switches the workout to miles as it opens.
    static var switchesToMiles: Bool { page?.hasPrefix("edit") == true && page?.hasSuffix("-miles") == true }

    static func builder(for page: String, plan: IntervalPlan?) -> (editing: WorkoutEditing, part: WorkoutPart?)? {
        let page = page.hasSuffix("-miles") ? String(page.dropLast("-miles".count)) : page
        switch page {
        case "new": return (.new, nil)
        case "edit-bottom", "edit-pick-display":
            guard let plan else { return (.new, nil) }
            return (.saved(plan), page == "edit-pick-display" ? .display : nil)
        case "edit", "edit-warmup", "edit-main", "edit-cooldown", "edit-pace":
            guard let plan else { return (.new, nil) }
            let part = page.hasPrefix("edit-") ? WorkoutPart(rawValue: String(page.dropFirst("edit-".count))) : nil
            return (.saved(plan), part)
        default: return nil
        }
    }

    /// The pages to open for `page`, given the first saved workout and today's coach session.
    static func path(for page: String, plan: IntervalPlan?, coach: CoachWorkout?) -> [WorkoutRoute] {
        switch page {
        case "distance": [.distance(.distanceRun)]
        case "time": [.time(.timedRun)]
        case "ready": [.distance(.distanceRun), .ready(.distance(name: "Distance Run", meters: 10_000))]
        case "timed-ready": [.time(.timedRun), .ready(.time(name: "Timed Run", seconds: 45 * 60))]
        case "free-ready": [.ready(.free(name: "Free Run"))]
        case "saved-ready": plan.map { [.ready(.saved($0))] } ?? []
        case "coach-ready": coach.map { [.ready(.coach($0))] } ?? []
        case "displays": [.displays]
        case "edit-display", "edit-display-picker", "edit-display-watch", "edit-display-lock": [.displays, .editDisplay(DisplayLibrary.current.defaultID)]
        default: []
        }
    }
}
#endif
