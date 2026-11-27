//
//  RecordingDetailsLayoutTests.swift
//  Wind Run
//

import CoreGraphics
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

    @Test func scrollsJustFarEnoughToClearTheFade() {
        let room = RecordingDetailsLayout.room
        // The live page: section ends at 783, the fade starts at 708.
        #expect(RecordingDetailsLayout.scrollTarget(sectionBottom: 783, visibleBottom: 708, offset: 1891, maxOffset: 2506) == 1891 + 75 + room)
        #expect(RecordingDetailsLayout.scrollTarget(sectionBottom: 400, visibleBottom: 708, offset: 1891, maxOffset: 2506) == nil)
    }

    @Test func neverScrollsPastTheEndOfThePage() {
        #expect(RecordingDetailsLayout.scrollTarget(sectionBottom: 900, visibleBottom: 700, offset: 1000, maxOffset: 1100) == 1100)
        // Already at the end: stays where it is rather than scrolling back up.
        #expect(RecordingDetailsLayout.scrollTarget(sectionBottom: 900, visibleBottom: 700, offset: 1000, maxOffset: 900) == 1000)
    }
}
