//
//  TraceToolTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
import UIKit
@testable import WindRun

/// The developer tool's small rules: the date a shared zip is named with, how a trace file is split and
/// searched, which screens the trace leaves out, and the page names screenshot scripts open Settings on.
@MainActor
struct TraceToolTests {
    // MARK: Dates

    @Test func aSharedZipIsNamedWithTheDateOnly() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let name = TraceZip.name(on: date)
        #expect(name == "Wind Run trace logs \(Trace.day(date))")
        #expect(try Regex("Wind Run trace logs [0-9]{4}-[0-9]{2}-[0-9]{2}").wholeMatch(in: name) != nil)
        #expect(!name.contains(":"))
    }

    // MARK: Reading a trace file

    @Test func aTraceFileSplitsIntoNumberedLinesWithoutBlanks() {
        let lines = TraceFileView.splitLines("a\n\nb\n")
        #expect(lines.map(\.id) == [0, 1])
        #expect(lines.map(\.text) == ["a", "b"])
        #expect(TraceFileView.splitLines("").isEmpty)
    }

    @Test func searchingIgnoresCaseAndKeepsEachLinesNumber() {
        let lines = TraceFileView.splitLines("App opened\nSettings › Done\nRun started")
        #expect(TraceFileView.matching(lines, "").map(\.id) == [0, 1, 2])
        let found = TraceFileView.matching(lines, "SETTINGS")
        #expect(found.map(\.id) == [1])
        #expect(found.map(\.text) == ["Settings › Done"])
        #expect(TraceFileView.matching(lines, "nothing like it").isEmpty)
    }

    // MARK: Screens left out

    @Test func systemContainersArentTracedAsScreens() {
        #expect(TraceHooks.isPlumbing(PrivateControllerStandIn()))
        #expect(TraceHooks.isPlumbing(EditingControllerStandIn()))
        #expect(TraceHooks.isPlumbing(InputControllerStandIn()))
        #expect(TraceHooks.isPlumbing(SystemKeyboardControllerStandIn()))
        #expect(TraceHooks.isPlumbing(PickerKeyboardControllerStandIn()))
        #expect(!TraceHooks.isPlumbing(SettingsControllerStandIn()))
        #expect(!TraceHooks.isPlumbing(UIViewController()))
    }

    // MARK: Settings pages

    /// The values `-settingsDemo` takes, which the README and the screenshot scripts use.
    @Test func settingsPagesKeepTheirLaunchNames() {
        #expect(SettingsPage.allCases.map(\.rawValue) == ["personalization", "health", "sensors", "appearance", "data", "starting-point", "legal", "privacy", "terms", "developer"])
    }
}

/// Named as the trace sees them, so each matches one of the rules for system containers, or none.
@objc(_UIStandInController) private final class PrivateControllerStandIn: UIViewController {}
@objc(UIEditingStandInController) private final class EditingControllerStandIn: UIViewController {}
@objc(UIInputStandInController) private final class InputControllerStandIn: UIViewController {}
@objc(UISystemKeyboardStandInController) private final class SystemKeyboardControllerStandIn: UIViewController {}
@objc(PickerKeyboardStandInController) private final class PickerKeyboardControllerStandIn: UIViewController {}
@objc(SettingsStandInController) private final class SettingsControllerStandIn: UIViewController {}
