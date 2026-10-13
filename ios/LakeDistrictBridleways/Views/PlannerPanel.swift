import CoreData
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let gpx = UTType(importedAs: "com.topografix.gpx")
}

/// A GPX file offered to the share sheet.
nonisolated struct GPXFile: Transferable {
    let name: String
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gpx) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try file.content.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.name }
    }
}

/// The planner panel: loop planning controls and breakdown, the reference loop and GPX tracks, and
/// saved loops. Shown in a bottom sheet on iPhone and in a side card on iPad.
struct PlannerPanel: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    @State private var showDisplay = false
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var showSaveDialog = false
    @State private var saveName = ""

    var body: some View {
        @Bindable var model = model
        Group {
            if compact {
                ScrollView { content }.scrollIndicators(.hidden)
            } else {
                // Size the card to its content when it fits, otherwise scroll.
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView { content }.scrollIndicators(.hidden)
                }
            }
        }
        .sheet(isPresented: $showDisplay) { DisplaySheet() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(item: $model.selectedWay) { info in WayDetailSheet(info: info) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.gpx, .xml, .data]) { result in
            if case .success(let url) = result { model.importGPX(from: url) }
        }
        .alert("Save loop", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveName)
            Button("Save") { model.saveCurrentLoop(named: saveName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The waypoints, route and any elevation data are stored on this device.")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            planningSection
            if compact, let stats = model.stats {
                StatsBox(stats: stats).padding(.vertical, 6)
            }
            routesSection
            SavedLoopsSection()
            attribution
        }
        .padding(16)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Lake District\nBridleways")
                    .font(.system(size: 19, weight: .bold).width(.condensed))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .lineSpacing(-2)
                Text("Loop planner · OpenStreetMap data")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                iconButton("square.3.layers.3d", label: "Display") { showDisplay = true }
                iconButton("gearshape", label: "Routing settings") { showSettings = true }
            }
        }
    }

    private func iconButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Theme.control, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.panelBorder))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(white: 0.82))
        .accessibilityLabel(label)
    }

    // MARK: Planning

    private var planningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PanelButton(model.isPlanning ? "Stop planning" : "Start planning", on: model.isPlanning) { model.togglePlanning() }
                    .disabled(!model.canPlan)
                PanelButton("Undo") { model.undoWaypoint() }.disabled(model.waypoints.isEmpty)
                PanelButton("Clear") { model.clearPlan() }.disabled(model.waypoints.isEmpty)
            }
            Text(model.isPlanning
                 ? "Tap the map to drop waypoints. The loop follows bridleways first, then footpaths, then roads, and returns to the start by a different way where it can. Drag a waypoint to move it, tap it to remove it."
                 : "Press Start planning, then tap the map to drop waypoints. Tap a path to see what it is.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineSpacing(2)

            if model.loadError != nil {
                Text(model.loadError ?? "").font(.footnote).foregroundStyle(.red)
            } else if model.isRouting {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Routing…").font(.footnote).foregroundStyle(Theme.muted) }
            } else if model.loopFailed {
                hint("No route found between those points.")
            } else if model.waypoints.count == 1 {
                hint("Add at least one more waypoint.")
            } else if let loop = model.loop {
                breakdown(loop)
            }

            HStack(spacing: 8) {
                PanelButton(model.isFetchingElevation ? "Fetching…" : "Get elevation") { model.fetchElevation() }
                    .disabled(model.loop == nil || model.isFetchingElevation || model.loopElevations != nil)
                if let gpx = model.plannedLoopGPX() {
                    ShareLink(item: GPXFile(name: "planned-loop.gpx", content: gpx), preview: SharePreview("Planned loop", image: Image(systemName: "map"))) {
                        PanelButtonLabel("Share GPX")
                    }
                    .buttonStyle(.plain)
                }
                PanelButton("Save") { saveName = ""; showSaveDialog = true }.disabled(model.loop == nil)
            }
            .padding(.top, 4)
            if let msg = model.elevationMessage { hint(msg) }
        }
    }

    private func breakdown(_ loop: LoopResult) -> some View {
        VStack(spacing: 0) {
            ForEach(BreakdownGroup.all) { group in
                let m = group.metres(in: loop.byCategory)
                if m > 0 {
                    row { HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(group.color).frame(width: 10, height: 10); Text(group.name) } } value: { Text(Format.km(m)) }
                }
            }
            row { Text("Total").bold() } value: { Text(Format.km(loop.length)).bold() }
        }
        .font(.system(size: 12))
        .padding(.top, 4)
    }

    private func row<L: View, V: View>(@ViewBuilder label: () -> L, @ViewBuilder value: () -> V) -> some View {
        HStack {
            label()
            Spacer()
            value().font(.system(size: 13, weight: .medium).width(.condensed)).monospacedDigit()
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelBorder).frame(height: 1) }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(2)
    }

    // MARK: Routes

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            @Bindable var model = model
            SectionTitle("Routes")
            if let ref = model.reference {
                Toggle(isOn: $model.showReference) {
                    HStack(spacing: 10) {
                        Capsule().fill(Theme.reference).frame(width: 26, height: 4)
                        Text("Loop from the reference image").font(.system(size: 13))
                        Spacer()
                        Text(Format.km(ref.length, decimals: 0)).font(.system(size: 13, weight: .medium).width(.condensed)).foregroundStyle(Theme.muted)
                    }
                }
                .toggleStyle(CheckToggleStyle())
            }
            HStack(spacing: 8) {
                PanelButton("Load GPX") { showImporter = true }
                if model.gpxTrack != nil { PanelButton("Clear GPX") { model.show(track: nil) } }
                PanelButton("Reset view") { model.fitFocusArea() }
            }
            if let track = model.gpxTrack {
                hint("\(track.name): \(Format.km(track.length))" + (track.ascent.map { ", \($0) m ascent" } ?? ""))
            } else {
                hint("Overlay your own GPX track to compare against the network.")
            }
            GPXTracksList()
        }
    }

    private var attribution: some View {
        Text("Map data © OpenStreetMap contributors. Fetched 13 Oct 2026. Cycling on a public footpath is not a right of way in England; always check the definitive map before relying on a right of way.")
            .font(.system(size: 10))
            .foregroundStyle(Theme.muted.opacity(0.8))
            .padding(.top, 8)
    }
}

// MARK: - Shared panel controls

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .medium).width(.condensed))
            .kerning(1.4)
            .foregroundStyle(Theme.muted)
    }
}

struct PanelButtonLabel: View {
    let title: String
    var on = false
    init(_ title: String, on: Bool = false) { self.title = title; self.on = on }
    var body: some View {
        Text(title)
            .font(.system(size: 13))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(on ? Theme.accent : Theme.control, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Theme.accent : Theme.panelBorder))
            .foregroundStyle(.white)
    }
}

struct PanelButton: View {
    let title: String
    var on = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, on: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.on = on; self.action = action
    }

    var body: some View {
        Button(action: action) { PanelButtonLabel(title, on: on) }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A checkbox-style toggle matching the web app's layer rows.
struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Theme.accent : Theme.muted)
                    .font(.system(size: 16))
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }
}

/// Imported GPX tracks stored in Core Data.
struct GPXTracksList: View {
    @Environment(AppModel.self) private var model
    @FetchRequest(fetchRequest: GPXTrack.allRequest()) private var tracks: FetchedResults<GPXTrack>

    var body: some View {
        if !tracks.isEmpty {
            VStack(spacing: 0) {
                ForEach(tracks) { track in
                    HStack {
                        Button {
                            model.show(track: model.gpxTrack?.id == track.id ? nil : track.summary)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: model.gpxTrack?.id == track.id ? "eye.fill" : "eye")
                                    .foregroundStyle(model.gpxTrack?.id == track.id ? Theme.planned : Theme.muted)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.name).font(.system(size: 13)).lineLimit(1)
                                    Text(Format.km(track.lengthMetres) + (track.ascentMetres.map { ", \($0) m" } ?? ""))
                                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) { model.delete(track: track) } label: {
                            Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 5)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelBorder).frame(height: 1) }
                }
            }
            .padding(.top, 4)
        }
    }
}
