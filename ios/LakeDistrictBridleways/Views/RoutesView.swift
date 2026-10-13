import CoreData
import SwiftUI
import UniformTypeIdentifiers

/// Saved routes and imported tracks. Tapping a saved route opens it in the planner.
struct RoutesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: PlannedLoop.savedLoopsRequest()) private var loops: FetchedResults<PlannedLoop>
    @FetchRequest(fetchRequest: GPXTrack.allRequest()) private var tracks: FetchedResults<GPXTrack>

    @State private var namePrompt: NamePrompt?
    @State private var showImporter = false
    @State private var confirmNew = false
    @State private var pendingDelete: PlannedLoop?

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                if loops.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No saved routes yet").font(.system(size: 15, weight: .medium))
                        Text("Plan a loop on the map and press Save route. It will appear here with its distance and climb.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Theme.control.opacity(0.6))
                } else {
                    ForEach(loops) { loop in
                        RouteRow(loop: loop, isOpen: model.loadedLoopID == loop.id)
                            .contentShape(Rectangle())
                            .onTapGesture { open(loop) }
                            .listRowBackground(model.loadedLoopID == loop.id ? Theme.controlOn : Theme.control.opacity(0.6))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { requestDelete(loop) } label: { Label("Delete", systemImage: "trash") }
                                Button { namePrompt = .renameSaved(loop) } label: { Label("Rename", systemImage: "pencil") }.tint(.gray)
                            }
                            .contextMenu {
                                Button("Open", systemImage: "map") { open(loop) }
                                Button("Rename…", systemImage: "pencil") { namePrompt = .renameSaved(loop) }
                                Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicate(loop: loop) }
                                if let gpx = gpx(for: loop) {
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
            } header: {
                Text("Saved routes").sectionTitleStyle()
            }

            Section {
                if let ref = model.reference {
                    Toggle(isOn: $model.showReference) {
                        TrackLabel(name: ref.name, color: Theme.reference, length: ref.length, ascent: ref.ascent, note: "Built in")
                    }
                    .toggleStyle(.switch)
                    .listRowBackground(Theme.control.opacity(0.6))
                }
                ForEach(tracks) { track in
                    let shown = model.gpxTrack?.id == track.id
                    Toggle(isOn: Binding(get: { shown }, set: { on in model.show(track: on ? track.summary : nil) })) {
                        TrackLabel(name: track.name, color: Theme.planned, length: track.lengthMetres, ascent: track.ascentMetres?.intValue,
                                   note: track.importedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    .toggleStyle(.switch)
                    .listRowBackground(Theme.control.opacity(0.6))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { model.delete(track: track) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                Button { showImporter = true } label: {
                    Label("Import a GPX file…", systemImage: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                }
                .listRowBackground(Theme.control.opacity(0.6))
            } header: {
                Text("Tracks shown on the map").sectionTitleStyle()
            } footer: {
                Text("Tracks are drawn for comparison and cannot be edited. Share a saved route to export it as GPX.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .tint(Theme.accent)
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.panel, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.hasUnsavedChanges, !model.waypoints.isEmpty { confirmNew = true } else { startNew() }
                } label: { Label("New route", systemImage: "plus") }
            }
        }
        .sheet(item: $namePrompt) { NameSheet(prompt: $0) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.gpx, .xml, .data]) { result in
            if case .success(let url) = result { model.importGPX(from: url); dismiss() }
        }
        .confirmationDialog("Start a new route?", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("Discard changes and start new", role: .destructive) { startNew() }
        } message: {
            Text("The route you are planning has unsaved changes.")
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete route", role: .destructive) { if let l = pendingDelete { model.delete(loop: l) }; pendingDelete = nil }
        }
    }

    private func open(_ loop: PlannedLoop) {
        guard model.canPlan else { return }
        model.load(loop: loop)
        dismiss()
    }

    private func startNew() {
        model.newRoute()
        dismiss()
    }

    private func requestDelete(_ loop: PlannedLoop) { pendingDelete = loop }

    private func gpx(for loop: PlannedLoop) -> String? {
        let coords = loop.coordinates
        guard coords.count > 1 else { return nil }
        let eles = loop.elevations
        let pts = eles != nil ? Geo.resample(coords, step: 100) : coords
        return GPX.document(name: loop.name, coords: pts, elevations: eles)
    }
}

/// One saved route: name, distance, climb, waypoints and when it was saved.
struct RouteRow: View {
    let loop: PlannedLoop
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOpen ? Theme.planned : Theme.muted)
                .frame(width: 30, height: 30)
                .background(Theme.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(loop.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                HStack(spacing: 0) {
                    Text(Format.km(loop.lengthMetres))
                    if let a = loop.ascent { Text(" · \(Format.metres(a)) climb") }
                    Text(" · \(loop.orderedWaypoints.count) waypoints")
                }
                .font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1)
                Text(loop.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.8))
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

struct TrackLabel: View {
    let name: String
    let color: Color
    let length: Double
    let ascent: Int?
    let note: String

    var body: some View {
        HStack(spacing: 12) {
            Capsule().fill(color).frame(width: 22, height: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                HStack(spacing: 0) {
                    Text(Format.km(length))
                    if let ascent { Text(" · \(Format.metres(ascent)) climb") }
                    Text(" · \(note)")
                }
                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
    }
}
