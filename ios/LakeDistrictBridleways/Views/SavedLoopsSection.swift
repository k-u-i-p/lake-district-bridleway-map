import CoreData
import SwiftUI

/// Loops saved to Core Data. Tapping one restores its waypoints and settings into the planner.
struct SavedLoopsSection: View {
    @Environment(AppModel.self) private var model
    @FetchRequest(fetchRequest: PlannedLoop.savedLoopsRequest()) private var loops: FetchedResults<PlannedLoop>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Saved loops")
            if loops.isEmpty {
                Text("Plan a loop and press Save to keep it here.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(loops) { loop in
                        HStack(spacing: 8) {
                            Button { model.load(loop: loop) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: model.loadedLoopID == loop.id ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                                        .foregroundStyle(model.loadedLoopID == loop.id ? Theme.planned : Theme.muted)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(loop.name).font(.system(size: 13)).lineLimit(1)
                                        Text(summary(loop)).font(.system(size: 11)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!model.canPlan)
                            if let gpx = gpx(for: loop) {
                                ShareLink(item: GPXFile(name: "\(loop.name).gpx", content: gpx), preview: SharePreview(loop.name, image: Image(systemName: "map"))) {
                                    Image(systemName: "square.and.arrow.up").font(.system(size: 13)).foregroundStyle(Theme.muted)
                                }
                                .buttonStyle(.plain)
                            }
                            Button(role: .destructive) { model.delete(loop: loop) } label: {
                                Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 5)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelBorder).frame(height: 1) }
                    }
                }
            }
        }
    }

    private func summary(_ loop: PlannedLoop) -> String {
        var s = Format.km(loop.lengthMetres)
        if let a = loop.ascent { s += ", \(a) m" }
        s += " · \(loop.orderedWaypoints.count) waypoints · " + loop.createdAt.formatted(date: .abbreviated, time: .omitted)
        return s
    }

    private func gpx(for loop: PlannedLoop) -> String? {
        let coords = loop.coordinates
        guard coords.count > 1 else { return nil }
        let eles = loop.elevations
        let pts = eles != nil ? Geo.resample(coords, step: 100) : coords
        return GPX.document(name: loop.name, coords: pts, elevations: eles)
    }
}
