import Foundation
import Testing
@testable import WindRun

/// "PR this year", "new PRs" and the starred bests on search rows.
@MainActor
struct WorkoutSearchPersonalBestsTests {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 7))!
    }

    private func run(_ date: Date, km: Double, minutes: Double, efforts: [Int: Double]? = nil, climb: Double? = nil,
                     sport: String = "running") -> WorkoutSearchRecord {
        WorkoutSearchRecord(id: UUID(), date: date, sport: sport, type: "free", title: "", notes: "",
                            distance: km * 1000, duration: minutes * 60, place: nil, terrain: [], climb: climb,
                            timeZone: pacific, bestEfforts: efforts)
    }

    private func search(_ query: String, in records: [WorkoutSearchRecord]) -> WorkoutSearchResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let intent = WorkoutSearchEngine.parse(query, now: day(2026, 11, 27), calendar: calendar)
        return WorkoutSearchEngine.search(intent, in: records)
    }

    // Last year's 5K stands all time. This year has a slower 5K, a long run with a fast 10K, and a half.
    private var history: (allTime5K: WorkoutSearchRecord, year5K: WorkoutSearchRecord, long: WorkoutSearchRecord,
                          half: WorkoutSearchRecord, easy: WorkoutSearchRecord) {
        (run(day(2025, 6, 1), km: 5, minutes: 22, efforts: [5_000: 1_320]),
         run(day(2026, 3, 10), km: 5, minutes: 23.5, efforts: [5_000: 1_410]),
         run(day(2026, 11, 24), km: 16, minutes: 90, efforts: [5_000: 1_440, 10_000: 2_970], climb: 240),
         run(day(2026, 10, 20), km: 21.1, minutes: 115, efforts: [5_000: 1_560, 10_000: 3_200, 21_098: 6_900]),
         run(day(2026, 11, 26), km: 6, minutes: 36, efforts: [5_000: 1_500]))
    }

    @Test func barePRWordsListTheBestsOfTheSearchedDates() {
        let h = history
        let all = [h.allTime5K, h.year5K, h.long, h.half, h.easy]
        for query in ["this year PR", "PR this year", "this year pr", "personal bests this year", "PB this year", "my PRs this year"] {
            let result = search(query, in: all)
            #expect(result.appliedIntent.sort == .personalBests, "\(query)")
            #expect(result.notUnderstood.isEmpty, "\(query)")
            #expect(result.ids == [h.year5K.id, h.long.id, h.half.id], "\(query)")
            #expect(result.closeIDs.isEmpty)
        }
        let result = search("this year PR", in: all)
        // This year's 5K is the year's best, not the all-time one.
        #expect(result.marks[h.year5K.id]?.contains(.init(kind: .effort(5_000), value: 1_410, allTime: false)) == true)
        // The long run's 10K and climb stand all time.
        #expect(result.marks[h.long.id]?.contains(.init(kind: .effort(10_000), value: 2_970, allTime: true)) == true)
        #expect(result.marks[h.long.id]?.contains(.init(kind: .climb, value: 240, allTime: true)) == true)
        // The half is the furthest and longest.
        let halfKinds = result.marks[h.half.id]?.map(\.kind) ?? []
        #expect(halfKinds.contains(.distance) && halfKinds.contains(.time) && halfKinds.contains(.effort(21_098)))
        // With no dates, the all-time bests.
        #expect(search("PRs", in: all).ids.first == h.allTime5K.id)
        #expect(search("personal best", in: all).marks[h.allTime5K.id]?.allSatisfy(\.allTime) == true)
    }

    @Test func newPRsAreTheWorkoutsThatSetABestAtTheTime() {
        let h = history
        let all = [h.allTime5K, h.year5K, h.long, h.half, h.easy]
        for query in ["new PR this year", "PRs set this year", "broke my PR this year"] {
            let result = search(query, in: all)
            #expect(result.appliedIntent.sort == .recordsSet, "\(query)")
            #expect(result.notUnderstood.isEmpty, "\(query)")
            // The easy 6 km beat nothing; the 5K in March beat last year's longest time.
            #expect(result.ids == [h.long.id, h.half.id, h.year5K.id], "\(query)")
        }
        let marks = search("new PR this year", in: all).marks
        // The half set a 10K best in October that the long run broke in November.
        #expect(marks[h.half.id]?.contains(.init(kind: .effort(10_000), value: 3_200, allTime: false)) == true)
        #expect(marks[h.long.id]?.contains(.init(kind: .effort(10_000), value: 2_970, allTime: true)) == true)
    }

    @Test func otherSearchesStarTheAllTimeBestsAWorkoutStillHolds() {
        let h = history
        let all = [h.allTime5K, h.year5K, h.long, h.half, h.easy]
        let result = search("last year", in: all)
        #expect(result.ids == [h.allTime5K.id])
        #expect(result.marks[h.allTime5K.id]?.contains(.init(kind: .effort(5_000), value: 1_320, allTime: true)) == true)
        #expect(search("this week", in: all).marks[h.easy.id] == nil)
    }

    @Test func aDistancePRCountsAtTheDistanceOrOverButNeverUnder() {
        // No route times: a whole run stands for 5K from 5 km to 5% over.
        let atFive = run(day(2026, 5, 1), km: 5.0, minutes: 25)
        let over = run(day(2026, 5, 2), km: 5.2, minutes: 24)
        let under = run(day(2026, 5, 3), km: 4.95, minutes: 20)
        let tooFar = run(day(2026, 5, 4), km: 5.4, minutes: 23)
        let result = search("5k PR", in: [atFive, over, under, tooFar])
        #expect(result.ids == [over.id, atFive.id])
        #expect(result.marks[over.id]?.contains(.init(kind: .effort(5_000), value: 24 * 60, allTime: true)) == true)
        #expect(search("this year PR", in: [under]).marks[under.id]?.contains { $0.kind == .effort(5_000) } == false)
        // Inside a route, a track short of 5 km by a meter has no 5K.
        let meters = stride(from: 0.0, through: 4_999, by: 100).map { $0 } + [4_999]
        let times = meters.map { $0 / 4 }
        let best = WorkoutSearchEfforts.best(times: times, meters: meters, stretches: Array(repeating: 0, count: meters.count),
                                             totalMeters: 4_999)
        #expect(best[5_000] == nil)
        #expect(best[1_000] != nil)
        let exact = stride(from: 0.0, through: 5_000, by: 100).map { $0 }
        #expect(WorkoutSearchEfforts.best(times: exact.map { $0 / 4 }, meters: exact,
                                          stretches: Array(repeating: 0, count: exact.count), totalMeters: 5_000)[5_000] != nil)
    }

    @Test func fastestPaceNeedsAKilometerAndSportsKeepTheirOwnBests() {
        let blip = run(day(2026, 6, 1), km: 0.4, minutes: 1)
        let tempo = run(day(2026, 6, 2), km: 8, minutes: 36)
        let ride = run(day(2026, 6, 3), km: 40, minutes: 80, sport: "cycling")
        let result = search("PR this year", in: [blip, tempo, ride])
        #expect(result.marks[blip.id]?.contains { $0.kind == .pace } != true)
        #expect(result.marks[tempo.id]?.contains { $0.kind == .pace } == true)
        // The ride is the furthest ride, but never the furthest run.
        #expect(result.marks[tempo.id]?.contains { $0.kind == .distance } == true)
        #expect(result.marks[ride.id]?.contains { $0.kind == .distance } == true)
    }

    @Test func aDistancePRStillRanksByThatDistanceAndStarsTheTop() {
        let h = history
        let all = [h.allTime5K, h.year5K, h.long, h.half, h.easy]
        let result = search("5k PR this year", in: all)
        #expect(result.appliedIntent.sort == .bestEffort)
        #expect(result.ids.first == h.year5K.id)
        #expect(result.marks[h.year5K.id]?.contains(.init(kind: .effort(5_000), value: 1_410, allTime: false)) == true)
        #expect(search("fastest 5k PR", in: all).appliedIntent.sort == .bestEffort)
    }
}
