//
//  LadderTypes.swift
//  Wind Run
//

import Foundation

/// Where a starting runner is: walking, the short run-walk, the ladder, or done (TI-2, BD-2).
enum LadderForm: String, Codable {
    /// TI-2a: brisk walks 3-5 times a week, +≤5 min a week, until 30 brisk minutes on 3 days.
    case walkStage
    /// TI-2b and BD-2a as one sequence: the short run-walk ratios, then the ladder to 30 min.
    case runWalk
    /// 30 min non-stop reached: the ladder is done.
    case done
}

/// One step of the run-walk sequence. The short run-walk ratios come first, then the ladder's
/// longest non-stop segment: 1, 2, 3, 4.5, 6, 8, 10, 12, 15, 20, 25, 30 min (BD-2a). AD-13b counts
/// steps back through both as one sequence.
struct RunWalkStep: Codable, Hashable {
    /// Running per repeat, in seconds.
    var runSeconds: Double
    /// Walking per repeat in seconds; nil is an open walk break that ends on tap, with a prompt at 1.5 min.
    var walkSeconds: Double?
    /// Session length in seconds, running and walking (15-20 min for the short run-walk, 20-30 for the ladder).
    var sessionSeconds: Double
    /// True for the short run-walk ratios (TI-2b).
    var isShortRunWalk: Bool

    /// The whole sequence, short run-walk first.
    static let sequence: [RunWalkStep] = {
        let shortRatios: [(Double, Double)] = [(15, 45), (20, 40), (25, 35), (30, 30)]
        let ladderMinutes: [Double] = [1, 2, 3, 4.5, 6, 8, 10, 12, 15, 20, 25, 30]
        let short = shortRatios.map { RunWalkStep(runSeconds: $0.0, walkSeconds: $0.1, sessionSeconds: 20 * 60, isShortRunWalk: true) }
        let ladder = ladderMinutes.map { minutes in
            RunWalkStep(runSeconds: minutes * 60, walkSeconds: minutes >= 30 ? 0 : nil, sessionSeconds: minutes >= 30 ? 30 * 60 : 25 * 60, isShortRunWalk: false)
        }
        return short + ladder
    }()

    /// The index of the ladder's 1-min step (NHS week 1, TI-2c).
    static let ladderStart = 4

    /// The index of a ladder step by its segment in minutes.
    static func ladderIndex(minutes: Double) -> Int {
        sequence.lastIndex { !$0.isShortRunWalk && $0.runSeconds <= minutes * 60 } ?? ladderStart
    }

    /// The last step: 30 min non-stop.
    static var lastIndex: Int { sequence.count - 1 }
}

/// The walk stage and ladder's progress (BD-2b, BD-2c, AD-18).
struct LadderState: Codable, Hashable {
    var form: LadderForm
    /// Walk stage: the current walk length in minutes.
    var walkMinutes: Double
    /// Index into `RunWalkStep.sequence`.
    var stepIndex: Int
    /// A restart never goes below the runner's first step (AD-13b).
    var firstStepIndex: Int
    /// Weeks spent on the current step (2-week steps at risk ≥2 or 65+, BD-2c).
    var weeksOnStep: Int
    /// Steps moved up so far, for Gentle's repeat week after every 3rd step.
    var stepsTaken: Int
    /// Set when the next week must repeat the step (RPE ≥6, a cold, an injury report).
    var holdNextWeek: Bool

    init(form: LadderForm, walkMinutes: Double = 0, stepIndex: Int = RunWalkStep.ladderStart, firstStepIndex: Int? = nil) {
        self.form = form
        self.walkMinutes = walkMinutes
        self.stepIndex = stepIndex
        self.firstStepIndex = firstStepIndex ?? stepIndex
        self.weeksOnStep = 0
        self.stepsTaken = 0
        self.holdNextWeek = false
    }

    var step: RunWalkStep { RunWalkStep.sequence[stepIndex.clamped(to: 0...RunWalkStep.lastIndex)] }
}
