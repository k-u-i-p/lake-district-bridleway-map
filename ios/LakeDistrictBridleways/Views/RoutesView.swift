import CoreData
import SwiftUI

/// Saved routes, with the built-in reference loop listed last. Tapping a route opens it in the planner
/// for viewing; Edit opens it with the planning controls shown.
struct RoutesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: PlannedLoop.savedLoopsRequest()) private var loops: FetchedResults<PlannedLoop>

    /// True when pushed inside the planner sheet, whose navigation bar is hidden. The view then draws its
    /// own header so the bar never animates in: with the system bar, the back button overflowed during the
    /// push and the bar dropped down once the sheet's safe area was applied.
    var embedded = false

    @State private var namePrompt: NamePrompt?
    @State private var confirmNew = false
    @State private var pendingDelete: PlannedLoop?

    var body: some View {
        VStack(spacing: 0) {
            if embedded { header }
            list
        }
        .background(Theme.panel)
        .tint(Theme.accent)
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(embedded)
        .toolbar(embedded ? .hidden : .automatic, for: .navigationBar)
        .toolbarBackground(Theme.panel, for: .navigationBar)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: requestNew) { Label("New route", systemImage: "plus") }
                }
            }
        }
        .sheet(item: $namePrompt) { NameSheet(prompt: $0) }
        .confirmationDialog("Start a new route?", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("Discard changes and start new", role: .destructive) { startNew() }
        } message: {
            Text("The route you are planning has unsaved changes.")
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete route", role: .destructive) { if let l = pendingDelete { model.delete(loop: l) }; pendingDelete = nil }
        }
    }

    /// Header drawn in place of the navigation bar, in the planner card's style.
    private var header: some View {
        HStack(spacing: 10) {
            circleButton("chevron.left", "Back") { dismiss() }
            Text("Routes").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            Spacer(minLength: 8)
            circleButton("plus", "New route", action: requestNew)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func circleButton(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Theme.control, in: Circle())
                .overlay(Circle().stroke(Theme.panelBorder))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }

    private var list: some View {
        List {
            Section {
                if loops.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No saved routes of your own yet").font(.system(size: 15, weight: .medium))
                        Text("Plan a loop on the map and press Save route. It will appear here with its distance and climb.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Theme.control.opacity(0.6))
                } else {
                    ForEach(loops) { loop in
                        RouteRow(name: loop.name, length: loop.lengthMetres, ascent: loop.ascent,
                                 detail: "\(loop.orderedWaypoints.count) waypoints · \(loop.updatedAt.formatted(date: .abbreviated, time: .omitted))",
                                 isOpen: model.loadedLoopID == loop.id, locked: false)
                            .contentShape(Rectangle())
                            .onTapGesture { open(loop) }
                            .listRowBackground(model.loadedLoopID == loop.id ? Theme.controlOn : Theme.control.opacity(0.6))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { requestDelete(loop) } label: { Label("Delete", systemImage: "trash") }
                                Button { namePrompt = .renameSaved(loop) } label: { Label("Rename", systemImage: "pencil") }.tint(.gray)
                            }
                            .contextMenu {
                                Button("Open", systemImage: "map") { open(loop) }
                                Button("Edit", systemImage: "pencil") { open(loop, edit: true) }
                                Button("Rename…", systemImage: "character.cursor.ibeam") { namePrompt = .renameSaved(loop) }
                                Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicate(loop: loop) }
                                if let gpx = gpx(name: loop.name, coords: loop.coordinates, elevations: loop.elevations) {
                                    ShareLink(item: GPXFile(name: "\(loop.name).gpx", content: gpx),
                                              preview: SharePreview(loop.name, image: Image(systemName: "map"))) {
                                        Label("Share GPX", systemImage: "square.and.arrow.up")
                                    }
                                }
                                Divider()
                                Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(loop) }
                            }
                    }
                }
                if let ref = model.reference {
                    RouteRow(name: ref.name, length: ref.length, ascent: ref.ascent, detail: "Built in · cannot be edited",
                             isOpen: model.loadedLoopID == ref.id, locked: true)
                        .contentShape(Rectangle())
                        .onTapGesture { openReference() }
                        .listRowBackground(model.loadedLoopID == ref.id ? Theme.controlOn : Theme.control.opacity(0.6))
                        .contextMenu {
                            Button("Open", systemImage: "map") { openReference() }
                            if let gpx = gpx(name: ref.name, coords: ref.coords, elevations: ref.profile) {
                                ShareLink(item: GPXFile(name: "\(ref.name).gpx", content: gpx),
                                          preview: SharePreview(ref.name, image: Image(systemName: "map"))) {
                                    Label("Share GPX", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                }
            } header: {
                Text("Saved routes").sectionTitleStyle()
            } footer: {
                Text("Tap a route to view it on the map. Press the pencil in the planner to change it. Share a route to export it as GPX.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func requestNew() {
        if model.hasUnsavedChanges, !model.waypoints.isEmpty { confirmNew = true } else { startNew() }
    }

    private func open(_ loop: PlannedLoop, edit: Bool = false) {
        guard model.canPlan else { return }
        model.load(loop: loop)
        if edit { model.beginEditing() }
        dismiss()
    }

    private func openReference() {
        model.viewReference()
        dismiss()
    }

    private func startNew() {
        model.newRoute()
        dismiss()
    }

    private func requestDelete(_ loop: PlannedLoop) { pendingDelete = loop }

    private func gpx(name: String, coords: [LatLon], elevations: [Double]?) -> String? {
        guard coords.count > 1 else { return nil }
        let pts = elevations != nil ? Geo.resample(coords, step: 100) : coords
        return GPX.document(name: name, coords: pts, elevations: elevations)
    }
}

/// One route in the list: name, distance, climb and a detail line. Locked rows are the built-in loop.
struct RouteRow: View {
    let name: String
    let length: Double
    let ascent: Int?
    let detail: String
    let isOpen: Bool
    let locked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: locked ? "lock.fill" : "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOpen ? Theme.planned : Theme.muted)
                .frame(width: 30, height: 30)
                .background(Theme.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                HStack(spacing: 0) {
                    Text(Format.km(length))
                    if let ascent { Text(" · \(Format.metres(ascent)) climb") }
                }
                .font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1)
                Text(detail)
                    .font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.8)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if isOpen {
                Text("OPEN").font(.system(size: 10, weight: .bold)).kerning(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.planned.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.planned)
            } else {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted.opacity(0.6))
            }
        }
        .padding(.vertical, 3)
    }
}
