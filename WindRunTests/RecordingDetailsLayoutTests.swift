//
//  RecordingDetailsLayoutTests.swift
//  Wind Run
//

import Testing
@testable import WindRun

struct RecordingDetailsLayoutTests {
    @Test func scrollsWhenTheOpenedSectionRunsUnderTheFade() {
        #expect(RecordingDetailsLayout.needsScroll(sectionBottom: 790, visibleBottom: 800))
        #expect(RecordingDetailsLayout.needsScroll(sectionBottom: 900, visibleBottom: 800))
    }

    @Test func staysPutWhenTheSectionAndItsRoomFit() {
        #expect(!RecordingDetailsLayout.needsScroll(sectionBottom: 800 - RecordingDetailsLayout.room, visibleBottom: 800))
        #expect(!RecordingDetailsLayout.needsScroll(sectionBottom: 400, visibleBottom: 800))
    }
}
