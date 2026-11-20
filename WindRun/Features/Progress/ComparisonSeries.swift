import CoreLocation
import Foundation

enum ComparisonMetric: String, CaseIterable {
    case pace = "Pace", heart = "Heart rate", cadence = "Cadence", elevation = "Elevation"

    func unit(_ distance: DistanceUnit) -> String {
        switch self {
        case .pace: "min/\(distance.symbol)"
        case .heart: "bpm"
        case .cadence: "spm"
        case .elevation: distance == .miles ? "ft" : "m"
        }
    }

    func value(_ raw: Double, unit: DistanceUnit) -> Double {
        switch self {
        case .pace: -unit.perUnit(raw)
        case .elevation: unit == .miles ? raw * 3.28084 : raw
        default: raw
        }
    }

    func label(_ plotted: Double) -> String {
        self == .pace ? RunFormat.duration(abs(plotted)) : Int(plotted.rounded()).formatted()
    }
}

struct ComparisonPoint: Identifiable {
    let id: Int
    let time: Double
    let meters: Double
    let value: Double
    let segment: Int
}

enum ComparisonAxis {
    case rep, time, distance
    func x(_ p: ComparisonPoint, unit: DistanceUnit) -> Double {
        switch self {
        case .rep: p.time
        case .time: p.time / 60
        case .distance: p.meters / unit.meters
        }
    }
}

/// Prepared once per selected session. Charts use the same filtered series as the run summary.
struct ComparisonSeries: Identifiable {
    let run: Run
    var id: UUID { run.runID }
    let lines: [ComparisonMetric: [ComparisonPoint]]
    let reps: [ComparisonMetric: [ComparisonPoint]]
    let elevation: ElevationSummary?
    let heartStats: HeartRateStats?
    let steps: Double?
    let coordinates: [[CLLocationCoordinate2D]]
    let work: [RunSection]
    let energy: CalorieEstimate?
    let repCount: Int

    func calories(bodyWeight: Double) -> Double? {
        run.activeCalories ?? (BodyWeight.range.contains(bodyWeight) ? energy?.kilocalories(bodyMass: bodyWeight) : nil)
    }

    init(_ run: Run) {
        self.run = run
        let fixes = run.activeRoute
        let buffers = run.chartPauseBuffers
        let cadence = run.cadenceSeries(buffers: buffers)
        let (heart, stats) = run.heartRateChart(buffers: buffers)
        let track = run.altitudeTrack(for: fixes)
        let height = Run.elevation(track)
        elevation = height
        energy = CalorieEstimator.estimate(Run.energyLegs(fixes: fixes, track: track))
        heartStats = stats
        steps = run.stepTotal
        coordinates = Dictionary(grouping: fixes, by: \.stretch).sorted { $0.key < $1.key }
            .map { $0.value.map { $0.sample.coordinate } }
        func points<T>(_ values: [T], time: KeyPath<T, Double>, value: KeyPath<T, Double>, segment: KeyPath<T, Int>) -> [ComparisonPoint] {
            var index = 0
            return values.enumerated().map { item, sample in
                let t = sample[keyPath: time]
                while index + 1 < fixes.count, fixes[index + 1].time <= t { index += 1 }
                var meters = fixes.isEmpty ? 0 : fixes[index].meters
                if index + 1 < fixes.count {
                    let a = fixes[index], b = fixes[index + 1]
                    if a.stretch == b.stretch, b.time > a.time {
                        meters += (b.meters - a.meters) * min(1, max(0, (t - a.time) / (b.time - a.time)))
                    }
                }
                return ComparisonPoint(id: item, time: t, meters: meters, value: sample[keyPath: value], segment: sample[keyPath: segment])
            }
        }
        var timeline: [ComparisonMetric: [ComparisonPoint]] = [
            .pace: points(Run.paceTimeline(fixes, buffers: buffers), time: \.activeTime, value: \.secondsPerKilometer, segment: \.segment),
            .cadence: points(cadence.chart, time: \.activeTime, value: \.stepsPerMinute, segment: \.segment),
            .heart: points(heart, time: \.activeTime, value: \.beatsPerMinute, segment: \.segment),
            .elevation: points(height?.profile ?? [], time: \.activeTime, value: \.meters, segment: \.segment)
        ]
        if let start = timeline[.elevation]?.first?.value {
            timeline[.elevation] = timeline[.elevation]?.map {
                ComparisonPoint(id: $0.id, time: $0.time, meters: $0.meters, value: $0.value - start, segment: $0.segment)
            }
        }
        lines = timeline
        let sections = run.sections.filter(\.isWork)
        work = sections
        var result: [ComparisonMetric: [ComparisonPoint]] = [:]
        let plan = run.intervalPlan?.timeline ?? []
        let workIndices = plan.indices.filter { plan[$0].kind == .work && !plan[$0].isWalk }
        repCount = workIndices.count
        for section in sections {
            guard let index = workIndices.firstIndex(of: section.id) else { continue }
            let rep = index + 1
            for metric in ComparisonMetric.allCases {
                let samples = (timeline[metric] ?? []).filter { $0.time > section.startTime && $0.time <= section.endTime }
                let value = metric == .pace ? section.pace : samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.value } / Double(samples.count)
                if let value {
                    let last = result[metric]?.last
                    let segment = (last?.segment ?? 0) + (last != nil && last?.id != rep - 1 ? 1 : 0)
                    result[metric, default: []].append(ComparisonPoint(id: rep, time: Double(rep), meters: section.meters, value: value, segment: segment))
                }
            }
        }
        reps = result
    }
}
