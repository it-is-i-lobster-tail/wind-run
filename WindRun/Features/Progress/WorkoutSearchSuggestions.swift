import Foundation

/// The searches the runner typed most recently, kept on this iPhone only: never in iCloud, settings sync,
/// backups of the app's settings to other devices, exports or traces. They can name places, so they stay here.
enum WorkoutSearchRecents {
    static let storageKey = "workoutSearchRecents"
    static let limit = 5

    static func load(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }

    /// Puts a search first, once, and keeps the newest few. Returns the new list.
    @discardableResult
    static func add(_ query: String, to defaults: UserDefaults = .standard) -> [String] {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = load(defaults)
        guard !typed.isEmpty, typed.count <= 200 else { return list }
        list.removeAll { $0.compare(typed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        list.insert(typed, at: 0)
        list = Array(list.prefix(limit))
        defaults.set(list, forKey: storageKey)
        return list
    }

    static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}

/// Searches to try, made from the runner's own history and distance unit, so each one finds something.
enum WorkoutSearchSuggestions {
    static func phrases(for records: [WorkoutSearchRecord], unit: DistanceUnit, now: Date = .now,
                        calendar: Calendar = .current) -> [String] {
        guard !records.isEmpty else { return ["Last week", unit == .miles ? "Runs over 3 miles" : "Runs over 5 km"] }
        var phrases: [String] = []
        // The town run in most, when it's more than one run.
        let cities = Dictionary(grouping: records.compactMap { $0.place?.city }.filter { !$0.isEmpty }, by: { $0 })
        if let top = cities.max(by: { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key }),
           top.value.count >= 2 {
            phrases.append("Runs in \(top.key)")
        }
        // A best effort the history has, the longest of 5K, 10K and the half that most runs reach.
        let efforts: [(Double, String)] = unit == .miles
            ? [(21_097.5, "Fastest half marathon"), (10_000, "Fastest 10K"), (5_000, "Fastest 5K"), (1_609.344, "Fastest mile")]
            : [(21_097.5, "Fastest half marathon"), (10_000, "Fastest 10K"), (5_000, "Fastest 5K"), (1_000, "Fastest 1K")]
        if let effort = efforts.first(where: { effort in
            records.filter { $0.bestEfforts?[WorkoutSearchEfforts.key(effort.0)] != nil }.count >= 3
        }) {
            phrases.append(effort.1)
        }
        // The part of the day most runs start in.
        let minutes = records.map { WorkoutSearchClock.minute(of: $0) }
        let mornings = minutes.filter { $0 >= 4 * 60 && $0 < 12 * 60 }.count
        let evenings = minutes.filter { $0 >= 17 * 60 && $0 < 21 * 60 }.count
        if max(mornings, evenings) * 3 >= records.count {
            phrases.append(mornings >= evenings ? "Morning runs" : "Evening runs")
        }
        // A whole distance in the runner's own unit, a little under their usual run, so it finds about half.
        let usual = records.map(\.distance).sorted()[records.count / 2]
        let step = unit == .miles ? DistanceUnit.miles.meters : 1000
        let amount = max(1, Int((usual * 0.9 / step).rounded(.down)))
        phrases.append("Runs over \(amount) \(unit == .miles ? (amount == 1 ? "mile" : "miles") : "km")")
        if records.contains(where: { $0.type == "intervals" }) { phrases.append("Intervals") }
        if records.contains(where: { calendar.isDate($0.date, equalTo: now, toGranularity: .weekOfYear) }) {
            phrases.append("This week")
        } else if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now),
                  records.contains(where: { calendar.isDate($0.date, equalTo: lastWeek, toGranularity: .weekOfYear) }) {
            phrases.append("Last week")
        }
        return Array(phrases.prefix(5))
    }
}
