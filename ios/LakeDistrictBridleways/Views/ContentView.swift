import SwiftUI

/// Full-screen map with the planner panel: a bottom sheet on iPhone, a floating card on iPad.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isRegular: Bool { sizeClass == .regular }
    private static let panelWidth: CGFloat = 320
    private static let sheetCollapsedHeight: CGFloat = 156

    var body: some View {
        ZStack(alignment: .top) {
            MapView(model: model, panelInsets: isRegular
                    ? UIEdgeInsets(top: 0, left: Self.panelWidth + 32, bottom: 0, right: 0)
                    : UIEdgeInsets(top: 0, left: 0, bottom: Self.sheetCollapsedHeight, right: 0))
                .ignoresSafeArea()

            if isRegular {
                HStack(alignment: .top, spacing: 0) {
                    PlannerPanel(compact: false)
                        .frame(width: Self.panelWidth)
                        .background(Theme.panel.opacity(0.94))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.panelBorder))
                        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
                    Spacer()
                }
                .padding(16)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if let stats = model.stats { StatsBox(stats: stats, fixedWidth: 300) }
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 36)
            }

            if let status = model.status {
                StatusPill(text: status)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.status)
        .sheet(isPresented: Binding(get: { !isRegular }, set: { _ in })) {
            PlannerPanel(compact: true)
                .presentationDetents([.height(Self.sheetCollapsedHeight), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationBackground(Theme.panel.opacity(0.96))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .onOpenURL { url in model.importGPX(from: url) }
        .task { await model.load() }
        .preferredColorScheme(.dark)
    }
}

struct StatusPill: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(.white)
            Text(text).font(.footnote)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.75), in: Capsule())
        .foregroundStyle(.white)
    }
}

#Preview {
    ContentView()
        .environment(AppModel(persistence: .preview, defaults: UserDefaults(suiteName: "preview")!))
        .environment(\.managedObjectContext, PersistenceController.preview.context)
}
