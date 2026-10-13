import SwiftUI

/// The first screen: which region to ride in. Each region has its own bundled network and its own
/// store of saved routes, so only the chosen region's routes are loaded.
struct RegionPicker: View {
    let choose: (Region) -> Void
    @AppStorage("lastRegion") private var lastRegion = ""

    var body: some View {
        ZStack {
            Theme.panel.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bens Mapper")
                            .font(.system(size: 34, weight: .bold))
                        Text("Choose where you are riding. Each region has its own map and its own saved routes.")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.muted)
                            .lineSpacing(2)
                    }
                    VStack(spacing: 12) {
                        ForEach(Region.allCases) { region in
                            Button { choose(region) } label: {
                                RegionCard(region: region,
                                           lastUsed: region.rawValue == lastRegion,
                                           savedRoutes: PersistenceController.forRegion(region).savedRouteCount)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Map data © OpenStreetMap contributors. Always check the definitive map before relying on a right of way.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted.opacity(0.8))
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
    }
}

/// One region: a photo of the National Park, its name, extent, how many routes are saved in it and
/// whether it was open last time.
struct RegionCard: View {
    let region: Region
    let lastUsed: Bool
    let savedRoutes: Int

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 132)
                .overlay {
                    Image(region.photo)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                }
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(region.name)
                        .font(.system(size: 20, weight: .bold))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                        .padding(.horizontal, 16).padding(.bottom, 12)
                }
                .overlay(alignment: .topTrailing) {
                    if lastUsed {
                        Text("LAST USED").font(.system(size: 9, weight: .bold)).kerning(0.8)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(Theme.planned)
                            .padding(10)
                    }
                }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(region.extent).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    Text(savedRoutes == 1 ? "1 saved route" : "\(savedRoutes) saved routes")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted.opacity(0.8))
                    Text(region.photoCredit)
                        .font(.system(size: 9)).foregroundStyle(Theme.muted.opacity(0.55))
                        .padding(.top, 2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted.opacity(0.6))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(lastUsed ? Theme.controlOn : Theme.control)
        .clipShape(shape)
        .overlay(shape.stroke(lastUsed ? Color.white.opacity(0.18) : Theme.panelBorder))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(region.name), \(savedRoutes) saved routes")
    }
}

#Preview {
    RegionPicker { _ in }
}
