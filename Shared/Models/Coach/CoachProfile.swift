//
//  CoachProfile.swift
//  Wind Run
//

import Foundation
import SwiftData

/// The runner's coach setup answers, kept between plans so the next setup doesn't ask them again.
///
/// One row, holding the answers as the coach's JSON. It syncs with runs and plans when iCloud Sync is on, so a new
/// iPhone starts from the same answers. Should two devices each make one before they sync, the newest wins.
@Model
final class CoachProfile {
    @Attribute(.externalStorage)
    var answersDataValue: Data?
    var updatedDateValue: Date = Date.now

    init(answersData: Data? = nil, updatedDate: Date = .now) {
        self.answersDataValue = answersData
        self.updatedDateValue = updatedDate
    }
}

extension CoachProfile {
    var answersData: Data? { answersDataValue }
    var updatedDate: Date { updatedDateValue }

    func store(_ data: Data, at date: Date = .now) {
        answersDataValue = data
        updatedDateValue = date
    }
}
