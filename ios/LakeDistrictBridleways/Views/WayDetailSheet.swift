import SwiftUI

/// Details for a tapped way.
struct WayDetailSheet: View {
    let info: WayInfo
    @Environment(\.dismiss) private var dismiss

    private var layer: DisplayLayer? { DisplayLayer.layer(forCategory: info.category) }
    private var categoryName: String { DisplayLayer.displayName(forCategory: info.category) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(info.way.name ?? "Unnamed \(categoryName.lowercased())")
                            .font(.system(size: 18, weight: .medium).width(.condensed))
                        Text(categoryName.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(0.5)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(layer?.color ?? Theme.muted, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.black)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    detail("Length", Format.kmShort(Double(info.way.length)))
                    if let v = info.way.prowRef { detail("PROW ref", v) }
                    if let v = info.way.surface { detail("Surface", v) }
                    if let v = info.way.tracktype { detail("Track grade", v) }
                    if let v = info.way.highway { detail("OSM highway", v) }
                }
                Section {
                    Link(destination: URL(string: "https://www.openstreetmap.org/way/\(info.way.osmID)")!) {
                        Label("View on OpenStreetMap", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .navigationTitle("Way")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }
    }
}
