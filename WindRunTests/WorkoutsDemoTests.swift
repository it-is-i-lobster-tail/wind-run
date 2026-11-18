//
//  WorkoutsDemoTests.swift
//  Wind Run Tests
//

#if DEBUG
import Foundation
import Testing
@testable import WindRun

/// The screenshot pages the Workout demo opens, worked out from the page name alone.
@MainActor
struct WorkoutsDemoTests {
    @Test func milesPagesOpenTheSameBuilderPage() throws {
        let opened = try #require(WorkoutsDemo.builder(for: "edit-main-miles", plan: nil))
        // With no saved workout, every edit page opens New Workout.
        guard case .new = opened.editing else {
            Issue.record("Expected New Workout")
            return
        }
        #expect(opened.part == nil)
    }

    @Test func newOpensTheBuilder() throws {
        let opened = try #require(WorkoutsDemo.builder(for: "new", plan: nil))
        guard case .new = opened.editing else {
            Issue.record("Expected New Workout")
            return
        }
        #expect(opened.part == nil)
    }

    @Test func otherPagesArentTheBuilder() {
        let opensBuilder = WorkoutsDemo.builder(for: "list", plan: nil) != nil
        #expect(!opensBuilder)
    }
}
#endif
