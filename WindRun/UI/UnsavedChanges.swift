//
//  UnsavedChanges.swift
//  Wind Run
//

import SwiftUI

extension View {
    /// For a sheet the runner fills in: with changes, a swipe down doesn't close it, and Cancel asks before the
    /// changes are thrown away. Cancel sets `isAsking` when there are changes; `discard` closes the sheet.
    func guardsUnsavedChanges(_ hasChanges: Bool, asking isAsking: Binding<Bool>, screen: String, discard: @escaping () -> Void) -> some View {
        interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard your changes?", isPresented: isAsking, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) {
                    Trace.tap(screen, "Discard changes?: Discard")
                    discard()
                }
                Button("Keep editing", role: .cancel) {
                    Trace.tap(screen, "Discard changes?: Keep editing")
                }
            }
    }
}
