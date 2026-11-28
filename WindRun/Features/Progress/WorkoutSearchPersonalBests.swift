import Foundation

/// Personal bests ("PRs") across a history: the furthest distance, the longest time moving, the fastest
/// average pace, the most climb and the fastest time over each standard distance. Each sport keeps its own.
nonisolated enum WorkoutSearchPersonalBests {
    /// One kind of best.
    enum Kind: Hashable, Comparable {
        case distance, time, pace, climb
        /// The fastest time over a standard distance, keyed by whole meters (`WorkoutSearchEfforts.key`).
        case effort(Int)

        /// The order rows and labels list them in: the efforts from short to long, then the whole-run bests.
        var order: Int {
            switch self {
            case .effort(let key): key
            case .distance: 1_000_000
            case .time: 1_000_001
            case .pace: 1_000_002
            case .climb: 1_000_003
            }
        }

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.order < rhs.order }
    }

    /// A best a workout holds, such as its 5K time.
    struct Mark: Hashable {
        var kind: Kind
        /// Meters for distance and climb, seconds for time and efforts, seconds per kilometer for pace.
        var value: Double
        /// True when nothing in the whole history beats it, not only the workouts searched.
        var allTime: Bool = false
    }

    /// Standard distances a bare "PR" search lists. 400 m and 800 m stay searchable by name ("800 m PR"), but
    /// GPS is too rough at that length to list them unasked.
    static let listedEfforts: [Int] = WorkoutSearchEfforts.distances.map(WorkoutSearchEfforts.key).filter { $0 >= 1_000 }

    /// The fastest average pace counts only from this far, so a short GPS blip is never a pace best.
    static let paceFloor: Double = 1_000

    /// How far over a standard distance a whole workout may run and still stand for it when its route gave no
    /// time for that distance, such as a 5.2 km treadmill run for a 5K. Never under: a 4.9 km run is no 5K.
    static let wholeRunAllowance = 0.05

    static var kinds: [Kind] { listedEfforts.map(Kind.effort) + [.distance, .time, .pace, .climb] }

    /// The fastest time the workout gives for a standard distance: the stretch inside the route, or else the
    /// whole workout when it ran that distance or up to 5% over.
    static func effort(_ record: WorkoutSearchRecord, key: Int) -> Double? {
        if let inside = record.bestEfforts?[key] { return inside }
        guard let target = WorkoutSearchEfforts.distances.first(where: { WorkoutSearchEfforts.key($0) == key }),
              record.distance >= target, record.distance <= target * (1 + wholeRunAllowance), record.duration > 0 else { return nil }
        return record.duration
    }

    static func value(_ kind: Kind, of record: WorkoutSearchRecord) -> Double? {
        switch kind {
        case .distance: record.distance > 0 ? record.distance : nil
        case .time: record.duration > 0 ? record.duration : nil
        case .pace: record.distance >= paceFloor ? record.pace : nil
        case .climb: (record.climb ?? 0) > 0 ? record.climb : nil
        case .effort(let key): effort(record, key: key)
        }
    }

    /// True when `a` beats `b`: further, longer and more climb are better; faster times and paces are better.
    static func beats(_ kind: Kind, _ a: Double, _ b: Double) -> Bool {
        switch kind {
        case .distance, .time, .climb: a > b
        case .pace, .effort: a < b
        }
    }

    /// The bests among `records`, per sport: one holder for each kind, the earliest on a tie. `history` is the
    /// whole history, which says which of them are all-time bests too.
    static func bests(in records: [WorkoutSearchRecord], history: [WorkoutSearchRecord], kinds: [Kind] = kinds) -> [UUID: [Mark]] {
        let standing = holders(history, kinds: kinds)
        var result: [UUID: [Mark]] = [:]
        for (sport, group) in Dictionary(grouping: records, by: \.sport) {
            for kind in kinds {
                guard let top = best(kind, in: group) else { continue }
                let allTime = standing[sport]?[kind]?.id == top.id
                result[top.id, default: []].append(Mark(kind: kind, value: top.value, allTime: allTime))
            }
        }
        return result.mapValues { $0.sorted { $0.kind < $1.kind } }
    }

    /// The bests each workout set when it was recorded: what it beat in every earlier workout of its sport. A
    /// sport's first workout sets each best it has a value for. All-time marks are the ones still standing.
    static func set(_ history: [WorkoutSearchRecord], kinds: [Kind] = kinds) -> [UUID: [Mark]] {
        let signature = signature(of: history, kinds: kinds)
        if let kept = keptSet, kept.signature == signature { return kept.marks }
        let standing = holders(history, kinds: kinds)
        var result: [UUID: [Mark]] = [:]
        for (sport, group) in Dictionary(grouping: history, by: \.sport) {
            let ordered = group.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString }
            for kind in kinds {
                var top: Double?
                for record in ordered {
                    guard let value = value(kind, of: record) else { continue }
                    if top.map({ beats(kind, value, $0) }) ?? true {
                        top = value
                        result[record.id, default: []].append(Mark(kind: kind, value: value,
                                                                   allTime: standing[sport]?[kind]?.id == record.id))
                    }
                }
            }
        }
        let marks = result.mapValues { $0.sorted { $0.kind < $1.kind } }
        keptSet = (signature, marks)
        return marks
    }

    /// The all-time bests still standing, per workout.
    static func standing(_ history: [WorkoutSearchRecord], kinds: [Kind] = kinds) -> [UUID: [Mark]] {
        set(history, kinds: kinds).compactMapValues { marks in
            let held = marks.filter(\.allTime)
            return held.isEmpty ? nil : held
        }
    }

    /// Kept while the history stays the same, so marking rows on each keystroke doesn't walk it again.
    private static var keptSet: (signature: Int, marks: [UUID: [Mark]])?

    private static func signature(of history: [WorkoutSearchRecord], kinds: [Kind]) -> Int {
        var hasher = Hasher()
        hasher.combine(kinds)
        for record in history {
            hasher.combine(record.id)
            hasher.combine(record.sport)
            hasher.combine(record.date)
            hasher.combine(record.distance)
            hasher.combine(record.duration)
            hasher.combine(record.climb)
            for kind in kinds { if case .effort(let key) = kind { hasher.combine(record.bestEfforts?[key]) } }
        }
        return hasher.finalize()
    }

    private static func best(_ kind: Kind, in group: [WorkoutSearchRecord]) -> (id: UUID, value: Double)? {
        var top: (id: UUID, value: Double, date: Date)?
        for record in group {
            guard let value = value(kind, of: record) else { continue }
            if let current = top {
                let better = beats(kind, value, current.value) || (value == current.value && record.date < current.date)
                if !better { continue }
            }
            top = (record.id, value, record.date)
        }
        return top.map { (id: $0.id, value: $0.value) }
    }

    private static func holders(_ history: [WorkoutSearchRecord], kinds: [Kind]) -> [String: [Kind: (id: UUID, value: Double)]] {
        var result: [String: [Kind: (id: UUID, value: Double)]] = [:]
        for (sport, group) in Dictionary(grouping: history, by: \.sport) {
            for kind in kinds { if let top = best(kind, in: group) { result[sport, default: [:]][kind] = top } }
        }
        return result
    }
}
