//
//  WorkoutEditorView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// What the workout sheet is working on.
enum WorkoutEditing: Identifiable {
    case new
    case saved(Workout)

    var id: String {
        switch self {
        case .new: "new"
        case .saved(let workout): "\(workout.persistentModelID.hashValue)"
        }
    }

    var workout: Workout? {
        if case .saved(let workout) = self { workout } else { nil }
    }
}

/// Adds a workout of the runner's own, such as "City Run", or changes or deletes one: a name and a type.
/// Nothing is stored until Save.
struct WorkoutEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editing: WorkoutEditing

    @State private var name: String
    @State private var type: WorkoutType
    @State private var isConfirmingDelete = false

    init(editing: WorkoutEditing) {
        self.editing = editing
        _name = State(initialValue: editing.workout?.name ?? "")
        _type = State(initialValue: editing.workout?.type ?? .distance)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("City Run", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onChange(of: name) { _, newName in
                            if newName.count > Workout.nameLimit { name = String(newName.prefix(Workout.nameLimit)) }
                        }
                } header: {
                    Text("Name")
                }

                Section {
                    Picker("Type", selection: $type) {
                        ForEach(WorkoutType.allCases) { type in
                            Label(type.name, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Type")
                } footer: {
                    Text(Self.typeNote(type))
                }

                if editing.workout != nil {
                    Section {
                        Button("Delete Workout", role: .destructive) {
                            Trace.tap("Workout editor", "Delete workout")
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(editing.workout == nil ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .traceScreen("Workout editor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Trace.tap("Workout editor", "Cancel")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Delete \(trimmedName.isEmpty ? "this workout" : trimmedName)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Workout", role: .destructive) {
                    Trace.tap("Workout editor", "Delete workout?: Delete Workout")
                    if let workout = editing.workout {
                        modelContext.delete(workout)
                        modelContext.saveQuietly()
                    }
                    dismiss()
                }
            } message: {
                Text("Runs you've done with it stay.")
            }
        }
    }

    /// What happens when the workout is picked.
    static func typeNote(_ type: WorkoutType) -> String {
        switch type {
        case .distance: "Pick how far each time you start it."
        case .time: "Pick how long each time you start it."
        case .intervals: "Pick one of your interval workouts each time you start it."
        case .free: "Starts a run with nothing to pick."
        }
    }

    private func save() {
        Trace.tap("Workout editor", "Save", ["type": type.rawValue, "new": editing.workout == nil])
        if let workout = editing.workout {
            workout.name = trimmedName
            workout.type = type
        } else {
            modelContext.insert(Workout(name: trimmedName, type: type))
        }
        modelContext.saveQuietly()
        dismiss()
    }
}

#Preview("New") {
    WorkoutEditorView(editing: .new)
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
