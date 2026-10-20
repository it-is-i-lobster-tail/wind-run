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

    /// Walk stage, then run-walk, then done.
    var order: Int {
        switch self {
        case .walkStage: 0
        case .runWalk: 1
        case .done: 2
        }
    }
}

/// One step of the run-walk sequence. The short run-walk ratios come first, then the ladder's
/// longest non-stop segment: 1, 2, 3, 4.5, 6, 8, 10, 12, 15, 20, 25, 30 min (BD-2a). AD-13b counts
/// steps back through both as one sequence.
struct RunWalkStep: Codable, Hashable {
    /// Running per repeat, in seconds.
    var runSeconds: Double
    /// Walking per repeat in seconds; nil is an open walk break that ends on tap, with a prompt at 1.5 min.
    var walkSeconds: Double?
    /// The longest session in seconds, running and walking: 20 min for the short run-walk and the 1-min step
    /// (TI-2b, TI-2c), 25 min from 2 to 10 min and 30 min from 12 min, inside BD-2a's 20-30 min.
    var sessionSeconds: Double
    /// True for the short run-walk ratios (TI-2b).
    var isShortRunWalk: Bool

    /// The whole sequence, short run-walk first.
    static let sequence: [RunWalkStep] = {
        let shortRatios: [(Double, Double)] = [(15, 45), (20, 40), (25, 35), (30, 30)]
        let ladderMinutes: [Double] = [1, 2, 3, 4.5, 6, 8, 10, 12, 15, 20, 25, 30]
        let short = shortRatios.map { RunWalkStep(runSeconds: $0.0, walkSeconds: $0.1, sessionSeconds: 20 * 60, isShortRunWalk: true) }
        let ladder = ladderMinutes.map { minutes in
            let session: Double = minutes < 2 ? 20 : (minutes < 12 ? 25 : 30)
            return RunWalkStep(runSeconds: minutes * 60, walkSeconds: minutes >= 30 ? 0 : nil, sessionSeconds: session * 60, isShortRunWalk: false)
        }
        return short + ladder
    }()

    /// The index of the ladder's 1-min step (NHS week 1, TI-2c).
    static let ladderStart = 4

    /// An open walk break counts as its 1.5-min prompt when a session is planned (BD-2a).
    static let openWalkSeconds: Double = 90

    /// The shortest short run-walk session, 15 min (TI-2b).
    static let shortestShortSession: Double = 15 * 60

    /// The shortest ladder session, 20 min: "the next session is the shortest" (BD-2a, AD-18).
    static let shortestLadderSession: Double = 20 * 60

    /// The index of a ladder step by its segment in minutes.
    static func ladderIndex(minutes: Double) -> Int {
        sequence.lastIndex { !$0.isShortRunWalk && $0.runSeconds <= minutes * 60 } ?? ladderStart
    }

    /// The step a planned session's first run and walk belong to: a short run-walk ratio by its run and
    /// walk, a ladder step by its segment.
    static func index(runSeconds: Double, walkSeconds: Double?) -> Int? {
        if let walkSeconds, let short = sequence.firstIndex(where: { step in
            step.isShortRunWalk && abs(step.runSeconds - runSeconds) < 1 && abs((step.walkSeconds ?? 0) - walkSeconds) < 1
        }) {
            return short
        }
        return sequence.firstIndex { !$0.isShortRunWalk && abs($0.runSeconds - runSeconds) < 1 }
    }

    /// The last step: 30 min non-stop.
    static var lastIndex: Int { sequence.count - 1 }

    /// The walk break a planned session counts.
    var plannedWalkSeconds: Double { walkSeconds ?? Self.openWalkSeconds }

    /// "15 seconds", "1 minute", "4.5 minutes".
    var runText: String {
        if runSeconds < 60 { return "\(Int(runSeconds)) seconds" }
        let minutes = runSeconds / 60
        if minutes == 1 { return "1 minute" }
        return "\(LadderPosition.minutesText(minutes)) minutes"
    }

    /// "15 seconds of running, then 45 of walking", "6 minutes of running at a time", "30 minutes non-stop".
    var summary: String {
        if isShortRunWalk { return "\(runText) of running, then \(Int(walkSeconds ?? 0)) of walking" }
        if runSeconds >= 30 * 60 { return "30 minutes non-stop" }
        return "\(runText) of running at a time"
    }
}

/// A place on the walk stage or the run-walk sequence: where a week is planned, where a restart goes.
struct LadderPosition: Codable, Hashable {
    var form: LadderForm
    /// Index into `RunWalkStep.sequence` (run-walk).
    var stepIndex: Int
    /// The walk length in minutes (walk stage).
    var walkMinutes: Double

    var step: RunWalkStep { RunWalkStep.sequence[stepIndex.clamped(to: 0 ... RunWalkStep.lastIndex)] }

    /// The walk stage comes before the run-walk sequence; shorter walks and earlier steps are easier.
    func isEasier(than other: LadderPosition) -> Bool {
        if form != other.form { return form.order < other.form.order }
        switch form {
        case .walkStage: return walkMinutes < other.walkMinutes - 0.01
        case .runWalk, .done: return stepIndex < other.stepIndex
        }
    }

    /// The easier of two positions.
    static func easier(_ first: LadderPosition, _ second: LadderPosition) -> LadderPosition {
        second.isEasier(than: first) ? second : first
    }

    /// "20-minute walks", "15 s run, 45 s walk", "4.5 min", "30 min non-stop".
    var name: String {
        switch form {
        case .walkStage:
            return "\(Self.minutesText(walkMinutes))-minute walks"
        case .runWalk, .done:
            let step = self.step
            if step.isShortRunWalk { return "\(Int(step.runSeconds)) s run, \(Int(step.walkSeconds ?? 0)) s walk" }
            if step.runSeconds >= 30 * 60 { return "30 min non-stop" }
            return "\(Self.minutesText(step.runSeconds / 60)) min"
        }
    }

    /// "4.5", "10": the ladder's half minutes kept, whole minutes without a decimal.
    static func minutesText(_ minutes: Double) -> String {
        let tenths = (minutes * 10).rounded()
        if tenths.truncatingRemainder(dividingBy: 10) == 0 { return "\(Int(tenths / 10))" }
        return "\(Int(tenths / 10)).\(Int(tenths.truncatingRemainder(dividingBy: 10)))"
    }
}

/// Why the ladder moved, for the "because" sentence.
enum LadderMoveReason: String, Codable {
    /// BD-2b: the week's sessions at RPE ≤5.
    case stepUp
    /// TI-2a: +5 min a week.
    case longerWalks
    /// TI-6: 30 brisk minutes on 3 days.
    case startRunWalk
    /// AD-18: two sessions at RPE ≥6.
    case hardSessions
    /// AD-18: the week felt "too hard".
    case tooHard
    /// AD-18's gap rows.
    case gap
    /// AD-18's one-tap easier restart.
    case easierRestart
    /// AD-18: the runner picked where to restart after a long gap.
    case chosenRestart
    /// AD-13b, AD-14c on the ladder: an Intense restart or a Severe return.
    case injury
    /// BD-2e: the first weeks' cap, when the step's segment doesn't fit it.
    case firstWeeks
    /// TI-6: 30 min non-stop, the ladder is done.
    case finished

    /// The step rules' week-end moves, which a later gap counts back from (AD-18). Restarts made during a gap
    /// are not: a gap never moves the runner back twice for the same days.
    var isEarned: Bool {
        switch self {
        case .stepUp, .longerWalks, .startRunWalk, .hardSessions, .tooHard: true
        case .gap, .easierRestart, .chosenRestart, .injury, .firstWeeks, .finished: false
        }
    }
}

/// One change of position, kept so a restart can find where the runner was before a gap or an injury.
struct LadderMove: Codable, Hashable {
    /// The first day of the new position.
    var date: Date
    var position: LadderPosition
    var reason: LadderMoveReason
}

/// A gap already handled (AD-18): the day of the last run before it, and the gap tier applied.
struct LadderGapMark: Codable, Hashable {
    var lastRunDay: Date
    /// 1: 8-14 days, 2: 15-28 days, 3: longer.
    var tier: Int
}

/// The steps back the runner picked for an Intense restart (AD-14b: any number, including none).
struct LadderInjuryChoice: Codable, Hashable {
    var reportID: UUID
    var stepsBack: Int
}

/// The walk stage and ladder's progress (BD-2b, BD-2c, AD-18).
struct LadderState: Codable, Hashable {
    var form: LadderForm
    /// Walk stage: the current walk length in minutes.
    var walkMinutes: Double
    /// Index into `RunWalkStep.sequence`.
    var stepIndex: Int
    /// The runner's first step in the run-walk sequence: a restart never goes below it (AD-13b, BD-2f).
    var firstStepIndex: Int
    /// The first walks' length: the walk stage's floor (BD-2f).
    var firstWalkMinutes: Double
    /// Weeks on the current position that passed BD-2b (2-week steps at risk ≥2, 65+, BMI ≥30, Gentle).
    var weeksOnStep: Int
    /// Where the plan started.
    var entry: LadderPosition
    /// Every change of position, oldest first.
    var history: [LadderMove]
    /// The last gap whose restart is in force, so a gap moves the runner back once for each tier (AD-18).
    var handledGap: LadderGapMark?
    /// Injury reports whose restart is in force (AD-13b, AD-14c).
    var handledInjuries: [UUID]
    var injuryChoices: [LadderInjuryChoice]
    /// AD-18 offers already answered, by key.
    var answeredOffers: [String]
    /// The 30-min non-stop run that finished the ladder; the plan joins the cycle when that week ends (TI-6).
    var finishedOn: Date?
    /// The last plan week whose end was applied, so a week's step is never applied twice.
    var lastEndedWeek: Int?

    init(form: LadderForm, walkMinutes: Double = 0, stepIndex: Int = RunWalkStep.ladderStart, firstStepIndex: Int? = nil) {
        self.form = form
        self.walkMinutes = walkMinutes
        self.stepIndex = stepIndex
        self.firstStepIndex = firstStepIndex ?? stepIndex
        self.firstWalkMinutes = walkMinutes
        self.weeksOnStep = 0
        self.entry = LadderPosition(form: form, stepIndex: stepIndex, walkMinutes: walkMinutes)
        self.history = []
        self.handledInjuries = []
        self.injuryChoices = []
        self.answeredOffers = []
    }

    var step: RunWalkStep { RunWalkStep.sequence[stepIndex.clamped(to: 0 ... RunWalkStep.lastIndex)] }

    var isActive: Bool { form != .done }

    /// The position in force now.
    var position: LadderPosition {
        LadderPosition(form: form, stepIndex: stepIndex, walkMinutes: walkMinutes)
    }

    /// The position in force on `date`, from the history.
    func position(on date: Date) -> LadderPosition {
        history.last { $0.date <= date }?.position ?? entry
    }

    /// The lowest position a restart from `position` may reach: the runner's first walks on the walk stage, and on
    /// run-walk the runner's first step, counting the short run-walk ratios and the ladder as one sequence. A restart
    /// never goes back from run-walk to the walk stage (AD-13b, BD-2f).
    func floor(for position: LadderPosition) -> LadderPosition {
        switch position.form {
        case .walkStage:
            return LadderPosition(form: .walkStage, stepIndex: position.stepIndex, walkMinutes: min(firstWalkMinutes, position.walkMinutes))
        case .runWalk, .done:
            return LadderPosition(form: .runWalk, stepIndex: min(position.stepIndex, firstStepIndex), walkMinutes: position.walkMinutes)
        }
    }

    /// `steps` steps back from `position`, never below its floor. On the walk stage a step is a week's
    /// 5 minutes of walk length (BD-2f).
    func back(_ steps: Int, from position: LadderPosition) -> LadderPosition {
        let floor = floor(for: position)
        var result = position
        switch position.form {
        case .walkStage:
            result.walkMinutes = max(floor.walkMinutes, position.walkMinutes - 5 * Double(max(0, steps)))
        case .runWalk, .done:
            result.form = .runWalk
            result.stepIndex = max(floor.stepIndex, position.stepIndex - max(0, steps))
        }
        return result
    }

    /// Moves to `position` from `date` on, and records it.
    mutating func move(to position: LadderPosition, on date: Date, reason: LadderMoveReason) {
        if position.form == .runWalk, form == .walkStage { firstStepIndex = position.stepIndex }
        if position.form == .runWalk, position.stepIndex < firstStepIndex, reason == .firstWeeks {
            firstStepIndex = position.stepIndex
        }
        if position != self.position { weeksOnStep = 0 }
        form = position.form
        stepIndex = position.stepIndex
        walkMinutes = position.walkMinutes
        let record = LadderMove(date: date, position: position, reason: reason)
        let at = history.firstIndex { $0.date > date } ?? history.endIndex
        history.insert(record, at: at)
    }
}
