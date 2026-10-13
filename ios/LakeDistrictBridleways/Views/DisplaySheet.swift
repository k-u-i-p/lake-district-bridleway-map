import SwiftUI

/// Base map, rights-of-way layers and overlays.
struct DisplaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Base map") {
                    Picker("Base map", selection: $model.baseMap) {
                        ForEach(BaseMap.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(model.baseMap.attribution).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Rights of way") {
                    ForEach(DisplayLayer.all) { layer in
                        Toggle(isOn: Binding(
                            get: { model.visibleLayers.contains(layer.key) },
                            set: { on in if on { model.visibleLayers.insert(layer.key) } else { model.visibleLayers.remove(layer.key) } }
                        )) {
                            HStack(spacing: 10) {
                                Swatch(layer: layer)
                                Text(layer.name)
                                Spacer()
                                Text(Format.km(model.layerLength(layer), decimals: 0))
                                    .font(.system(size: 13, weight: .medium).width(.condensed))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Overlays") {
                    Toggle(model.region.peaksTitle, isOn: $model.showPeaks)
                    Toggle("Valley & lake labels", isOn: $model.showLabels)
                    Toggle("Focus area outline", isOn: $model.showFocus)
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct Swatch: View {
    let layer: DisplayLayer
    var body: some View {
        let h: CGFloat = layer.thin ? 2 : 4
        Group {
            if layer.dashed {
                HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Rectangle().fill(layer.color).frame(width: 6, height: h) } }
            } else {
                Capsule().fill(layer.color).frame(height: h)
            }
        }
        .frame(width: 26, height: 6)
    }
}
