import SwiftUI

/// Full-screen map for the open region, with floating map controls and the planner: a bottom sheet
/// on iPhone, a side card on iPad. The region pill at the top left returns to the region picker.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var detent: PresentationDetent = .height(ContentView.collapsedHeight)
    /// Leaves this region for the region picker.
    var changeRegion: () -> Void = {}

    private var isRegular: Bool { sizeClass == .regular }
    static let panelWidth: CGFloat = 340
    static let collapsedHeight: CGFloat = 168

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MapView(model: model, panelInsets: isRegular
                    ? UIEdgeInsets(top: 0, left: Self.panelWidth + 32, bottom: 0, right: 0)
                    : UIEdgeInsets(top: 0, left: 0, bottom: Self.collapsedHeight, right: 0))
                .ignoresSafeArea()

            MapControls()
                .padding(.top, 8)
                .padding(.trailing, 12)

            RegionPill(name: model.region.name, action: changeRegion)
                .padding(.top, 8)
                .padding(.leading, isRegular ? Self.panelWidth + 32 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRegular {
                VStack(spacing: 0) {
                    PlannerPanel(compact: false, detent: .constant(.large))
                        .frame(width: Self.panelWidth)
                        .background(Theme.panel.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.panelBorder))
                        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .overlay(alignment: .top) {
            // Below the region pill and map controls, which share the top row.
            if let status = model.status {
                StatusPill(text: status, busy: true).padding(.top, 58).transition(.opacity)
            } else if model.isPlanning {
                StatusPill(text: model.waypoints.isEmpty ? "Tap the map to add your first waypoint" : "Tap the map to add waypoints", busy: false)
                    .padding(.top, 58).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.status)
        .animation(.easeInOut(duration: 0.2), value: model.isPlanning)
        .sheet(isPresented: Binding(get: { !isRegular }, set: { _ in })) {
            PlannerPanel(compact: true, detent: $detent)
                .presentationDetents([.height(Self.collapsedHeight), .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationBackground(Theme.panel.opacity(0.97))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .task { await model.load() }
        .preferredColorScheme(.dark)
    }
}

/// Round buttons floating over the map: layers, routing settings, fit-to-route and your location.
struct MapControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            control("square.3.layers.3d", "Map layers") { model.activeSheet = .display }
            control("slider.horizontal.3", "Routing settings") { model.activeSheet = .settings }
            control(model.loop != nil ? "point.topleft.down.to.point.bottomright.curvepath" : "arrow.up.left.and.down.right.magnifyingglass",
                    model.loop != nil ? "Fit route" : "Fit the \(model.region.name)") { model.fitToRoute() }
            control(locationIcon, locationLabel, tint: model.locationTracking == .off ? .white : .blue) { model.cycleLocationTracking() }
        }
    }

    private var locationIcon: String {
        switch model.locationTracking {
        case .off: "location"
        case .follow: "location.fill"
        case .heading: "location.north.line.fill"
        }
    }

    private var locationLabel: String {
        switch model.locationTracking {
        case .off: "Show my location"
        case .follow: "Following my location"
        case .heading: "Following my location and heading"
        }
    }

    private func control(_ system: String, _ label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 42, height: 42)
                .background(Theme.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .accessibilityLabel(label)
    }
}

/// The open region's name, floating at the top left of the map. Tapping it goes back to the picker.
struct RegionPill: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                Text(name).font(.system(size: 14, weight: .medium))
            }
            .padding(.leading, 10)
            .padding(.trailing, 13)
            .frame(height: 42)
            .background(Theme.panel.opacity(0.88), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel("Change region")
    }
}

struct StatusPill: View {
    let text: String
    var busy = true
    var body: some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "hand.tap").font(.footnote) }
            Text(text).font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.78), in: Capsule())
        .foregroundStyle(.white)
    }
}

#Preview {
    ContentView()
        .environment(AppModel(region: .lakeDistrict, persistence: .preview, defaults: UserDefaults(suiteName: "preview")!))
        .environment(\.managedObjectContext, PersistenceController.preview.context)
}
