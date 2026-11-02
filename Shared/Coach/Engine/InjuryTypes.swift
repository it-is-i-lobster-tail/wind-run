//
//  InjuryTypes.swift
//  Wind Run
//

import Foundation

/// How bad an injury is, as the runner reports it (AD-13). The coach never diagnoses.
enum InjuryLevel: Int, Codable, CaseIterable, Comparable {
    case mild
    case intense
    case severe

    var name: String {
        switch self {
        case .mild: "Mild"
        case .intense: "Intense"
        case .severe: "Severe"
        }
    }

    /// The text under each choice on "How bad is it?"
    var detail: String {
        switch self {
        case .mild: "Some pain that fades within about 30 minutes after a run, like light shin splints."
        case .intense: "You think you may need a physio, or you're seeing one and you're cleared to train."
        case .severe: "You need to stop: it hurts too much to run, or you're not cleared to run."
        }
    }

    static func < (lhs: InjuryLevel, rhs: InjuryLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where it hurts (optional). Used only for wording, route changes, the area memory and the
/// same-area count, never for a diagnosis (AD-13).
enum InjuryArea: String, Codable, CaseIterable {
    case footAnkle
    case shin
    case calfAchilles
    case knee
    case thighHamstring
    case hipGroin
    case back
    case other

    var name: String {
        switch self {
        case .footAnkle: "foot or ankle"
        case .shin: "shin"
        case .calfAchilles: "calf or Achilles"
        case .knee: "knee"
        case .thighHamstring: "thigh or hamstring"
        case .hipGroin: "hip or groin"
        case .back: "back"
        case .other: "other"
        }
    }
}

/// "Are you medically cleared to keep training?" (AD-13b)
enum ClearanceAnswer: String, Codable, CaseIterable {
    case yes
    case no
    case notSure

    var name: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        case .notSure: "Not sure"
        }
    }
}
