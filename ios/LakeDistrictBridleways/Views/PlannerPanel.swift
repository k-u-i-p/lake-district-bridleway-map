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

/// The planner: the route being planned, with the saved routes pushed on top (iPhone sheet) or
/// shown in a separate sheet (iPad card, which is sized to its content).
struct PlannerPanel: View {
    @Environment(AppModel.self) private var model
    let compact: Bool
    @Binding var detent: PresentationDetent
    @State private var showRoutes = false

    var body: some View {
        @Bindable var model = model
        Group {
            if compact {
                NavigationStack {
                    PlanView(openRoutes: {
                        if detent == .height(ContentView.collapsedHeight) { detent = .medium }
                        showRoutes = true
                    })
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(isPresented: $showRoutes) { RoutesView(embedded: true) }
                }
            } else {
                ViewThatFits(in: .vertical) {
                    PlanView(openRoutes: { showRoutes = true }, scrolls: false)
                    PlanView(openRoutes: { showRoutes = true })
                }
                .sheet(isPresented: $showRoutes) {
                    NavigationStack {
                        RoutesView()
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showRoutes = false } } }
                    }
                    .tint(Theme.accent)
                }
            }
        }
        .tint(Theme.accent)
        .sheet(item: $model.activeSheet) { sheet in
            switch sheet {
            case .display: DisplaySheet()
            case .settings: SettingsSheet()
            }
        }
        .sheet(item: $model.selectedWay) { info in WayDetailSheet(info: info) }
    }
}

/// The route being planned: name, summary, planning controls, elevation, surface mix and saving.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    let openRoutes: () -> Void
    /// False lays the content out at its natural height, for a card that fits its content.
    var scrolls = true

    @State private var namePrompt: NamePrompt?
    @State private var confirmClear = false
    @State private var confirmEndEditing = false

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }.scrollIndicators(.hidden)
            } else {
                content
            }
        }
        .sheet(item: $namePrompt) { prompt in
            NameSheet(prompt: prompt)
        }
        .confirmationDialog("Remove all \(model.waypoints.count) waypoints?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear route", role: .destructive) { model.clearPlan() }
        }
        .confirmationDialog("Keep your changes to “\(model.displayName)”?", isPresented: $confirmEndEditing, titleVisibility: .visible) {
            Button("Save changes") { model.saveChanges(); model.endEditing() }
            Button("Discard changes", role: .destructive) { model.discardChanges() }
        }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 14) {
                header
                summary
                if model.isEditing { planningButtons }
                if model.loadError != nil {
                    Text(model.loadError ?? "").font(.footnote).foregroundStyle(.red)
                } else if model.isReadOnly {
                    hint("This loop is built in. It can be viewed and shared but not changed.")
                } else if model.isPlanning {
                    hint("Tap the map to add waypoints. Drag a marker to move it, tap it to remove it. The loop returns to the start by a different way where it can.")
                } else if !model.isEditing {
                    hint("Press the pencil to change this route's waypoints or settings.")
                } else if model.waypoints.isEmpty {
                    hint("Press Add waypoints, then tap the map where you want to ride. Tap any path to see what it is.")
                }
                if model.loop != nil {
                    elevationCard
                    RouteMix(byCategory: model.loop?.byCategory ?? [:], total: model.loop?.length ?? 0)
                    saveRow
                }
                attribution
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 20)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                namePrompt = canRename ? .rename(current: model.displayName) : nil
            } label: {
                HStack(spacing: 7) {
                    Text(model.displayName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(model.routeName == nil ? Theme.muted : .white)
                        .lineLimit(1)
                    if model.isSavedRouteOpen && model.hasUnsavedChanges {
                        Circle().fill(Theme.planned).frame(width: 7, height: 7)
                            .accessibilityLabel("Unsaved changes")
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canRename)
            Spacer(minLength: 8)
            if model.canEdit {
                Button {
                    if !model.isEditing {
                        model.beginEditing()
                    } else if model.hasUnsavedChanges {
                        confirmEndEditing = true
                    } else {
                        model.endEditing()
                    }
                } label: {
                    Image(systemName: model.isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(model.isEditing ? Theme.controlOn : Theme.control, in: Circle())
                        .overlay(Circle().stroke(model.isEditing ? Color.white.opacity(0.25) : Theme.panelBorder))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel(model.isEditing ? "Finish editing" : "Edit route")
            }
            Button(action: openRoutes) {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet")
                    Text("Routes")
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Theme.control, in: Capsule())
                .overlay(Capsule().stroke(Theme.panelBorder))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }

    /// The name can be changed while editing, once there is a route or a saved route to name.
    private var canRename: Bool {
        model.isEditing && !model.isReadOnly && (model.loop != nil || model.isSavedRouteOpen)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            if model.isRouting {
                ProgressView().controlSize(.small).padding(.trailing, 8)
                Text("Routing…")
            } else if model.loopFailed {
                Text("No route between those points. Try moving a waypoint.")
            } else if let loop = model.loop {
                Text(Format.km(loop.length)).foregroundStyle(.white)
                if let a = model.loopAscent {
                    Text(" · ")
                    Text("\(Format.metres(a)) climb").foregroundStyle(.white)
                } else if model.isFetchingElevation {
                    Text(" · ")
                    Text("climb…")
                }
                if !model.waypoints.isEmpty { Text(" · \(model.waypoints.count) waypoints") }
            } else if model.waypoints.count == 1 {
                Text("One waypoint. Add another to make a loop.")
            } else {
                Text("No waypoints yet")
            }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
        .monospacedDigit()
    }

    private var planningButtons: some View {
        HStack(spacing: 8) {
            PanelButton(model.isPlanning ? "Done" : (model.waypoints.isEmpty ? "Add waypoints" : "Add more"),
                        icon: model.isPlanning ? "checkmark" : "plus",
                        style: model.isPlanning ? .on : .prominent) { model.togglePlanning() }
                .disabled(!model.canPlan)
            PanelButton("Undo", icon: "arrow.uturn.backward") { model.undoWaypoint() }
                .disabled(model.waypoints.isEmpty)
            PanelButton("Clear") {
                if model.waypoints.count > 1 { confirmClear = true } else { model.clearPlan() }
            }
            .disabled(model.waypoints.isEmpty)
        }
    }

    // MARK: Elevation

    private var elevationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ELEVATION").sectionTitleStyle()
                Spacer()
                if let a = model.loopAscent {
                    Text("\(Format.metres(a)) climb").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                }
            }
            switch model.elevationState {
            case .ready:
                if let profile = model.loopElevations, profile.count > 1 {
                    ElevationProfile(elevations: profile).frame(height: 72)
                }
            case .fetching(let fraction):
                HStack(spacing: 10) {
                    ProgressView(value: fraction).tint(Theme.planned)
                    Text("\(Int(fraction * 100))%").font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit()
                }
                .frame(height: 72)
            case .failed:
                HStack {
                    Text("Elevation is unavailable right now (the free lookup is rate-limited).")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Retry") { model.fetchElevation() }.font(.system(size: 13, weight: .medium))
                }
                .frame(height: 72)
            case .none:
                Text(model.isReadOnly ? "No elevation data for this loop." : "Elevation will load shortly…")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).frame(height: 72)
            }
        }
        .padding(12)
        .background(Theme.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Saving

    /// Share is always available. Saving, renaming and save-as-new only appear while editing.
    private var saveRow: some View {
        HStack(spacing: 8) {
            if model.isEditing, model.isSavedRouteOpen {
                PanelButton(model.hasUnsavedChanges ? "Save changes" : "Saved",
                            icon: model.hasUnsavedChanges ? "bookmark.fill" : "checkmark",
                            style: model.hasUnsavedChanges ? .prominent : .standard) { model.saveChanges() }
                    .disabled(!model.hasUnsavedChanges)
            } else if model.isEditing {
                PanelButton("Save route", icon: "bookmark.fill", style: .prominent) {
                    namePrompt = .save(suggested: model.suggestedName())
                }
            }
            if let gpx = model.plannedLoopGPX() {
                ShareLink(item: GPXFile(name: model.gpxFileName, content: gpx),
                          preview: SharePreview(model.displayName, image: Image(systemName: "map"))) {
                    PanelButtonLabel("Share", icon: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
            if model.isEditing, model.isSavedRouteOpen {
                Menu {
                    Button("Rename…", systemImage: "character.cursor.ibeam") { namePrompt = .rename(current: model.displayName) }
                    Button("Save as new route…", systemImage: "plus.square.on.square") { namePrompt = .save(suggested: model.displayName + " copy") }
                } label: {
                    PanelButtonLabel("", icon: "ellipsis")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineSpacing(2)
    }

    private var attribution: some View {
        Text("Map data © OpenStreetMap contributors. \(model.region.accessNote)")
            .font(.system(size: 10))
            .foregroundStyle(Theme.muted.opacity(0.8))
            .padding(.top, 6)
    }
}

// MARK: - Shared panel controls

extension Text {
    func sectionTitleStyle() -> Text {
        self.font(.system(size: 11, weight: .medium).width(.condensed)).kerning(1.4).foregroundStyle(Theme.muted)
    }
}

enum PanelButtonStyle { case standard, prominent, on }

struct PanelButtonLabel: View {
    let title: String
    var icon: String? = nil
    var style: PanelButtonStyle = .standard

    init(_ title: String, icon: String? = nil, style: PanelButtonStyle = .standard) {
        self.title = title; self.icon = icon; self.style = style
    }

    private var fill: Color {
        switch style {
        case .standard: Theme.control
        case .prominent: Theme.accent
        case .on: Theme.controlOn
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
            if !title.isEmpty { Text(title) }
        }
        .font(.system(size: 14, weight: style == .standard ? .regular : .medium))
        .padding(.horizontal, title.isEmpty ? 11 : 13)
        .frame(height: 38)
        .background(fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(style == .on ? Color.white.opacity(0.25) : Theme.panelBorder))
        .foregroundStyle(.white)
    }
}

struct PanelButton: View {
    let title: String
    var icon: String? = nil
    var style: PanelButtonStyle = .standard
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, icon: String? = nil, style: PanelButtonStyle = .standard, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.style = style; self.action = action
    }

    var body: some View {
        Button(action: action) { PanelButtonLabel(title, icon: icon, style: style) }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A checkbox-style toggle for layer-like rows.
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
