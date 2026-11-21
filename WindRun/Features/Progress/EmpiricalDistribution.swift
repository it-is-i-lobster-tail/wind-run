import Foundation

/// Each plotted observation contributes 1/N. Equal values produce one jump at their shared threshold.
struct EmpiricalDistribution {
    struct Step: Identifiable {
        let value: Double
        let count: Int
        var id: Double { value }
    }

    let count: Int
    let steps: [Step]

    init(_ values: [Double]) {
        let sorted = values.filter(\.isFinite).sorted()
        count = sorted.count
        steps = sorted.indices.compactMap { index in
            if index + 1 < sorted.count, sorted[index] == sorted[index + 1] { return nil }
            return Step(value: sorted[index], count: index + 1)
        }
    }

    func count(atOrBelow threshold: Double) -> Int {
        steps.last { $0.value <= threshold }?.count ?? 0
    }
}
