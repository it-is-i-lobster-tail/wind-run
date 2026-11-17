//
//  SectionReselection.swift
//  Wind Run
//

import SwiftUI

extension EnvironmentValues {
    /// How many times the runner has tapped the section switcher's button for the section they're already
    /// in. Each tap takes the section back to its first screen, as the system tab bar does.
    @Entry var sectionReselections = 0
}
