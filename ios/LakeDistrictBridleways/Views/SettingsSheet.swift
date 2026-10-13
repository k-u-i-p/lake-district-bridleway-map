import SwiftUI

/// Routing penalties: how strongly footpaths, roads and already-ridden tracks are avoided.
struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("Footpath penalty", selection: $model.routing.footpathPenalty) {
                        Text("×2 (relaxed)").tag(2.0); Text("×3").tag(3.0); Text("×5").tag(5.0); Text("×10 (avoid)").tag(10.0)
                    }
                    Picker("Road penalty", selection: $model.routing.roadPenalty) {
                        Text("×3 (relaxed)").tag(3.0); Text("×5").tag(5.0); Text("×8").tag(8.0); Text("×15 (avoid)").tag(15.0)
                    }
                    Picker("Re-riding penalty", selection: $model.routing.reridePenalty) {
                        Text("none").tag(1.0); Text("×2").tag(2.0); Text("×4").tag(4.0); Text("×10 (avoid)").tag(10.0)
                    }
                } footer: {
                    Text("Penalties multiply the distance of each type of way when choosing a route. Bridleways and byways always count ×1. The re-riding penalty discourages the return leg from using tracks already ridden. Changing a setting re-routes the current loop.")
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Routing settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
