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
                        Text("Bridleway Map")
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

/// One region: name, extent, how many routes are saved in it and whether it was open last time.
struct RegionCard: View {
    let region: Region
    let lastUsed: Bool
    let savedRoutes: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: region.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 46, height: 46)
                .background(Theme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(region.name).font(.system(size: 18, weight: .semibold))
                Text(region.extent).font(.system(size: 13)).foregroundStyle(Theme.muted)
                HStack(spacing: 8) {
                    Text(savedRoutes == 1 ? "1 saved route" : "\(savedRoutes) saved routes")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted.opacity(0.8))
                    if lastUsed {
                        Text("LAST USED").font(.system(size: 9, weight: .bold)).kerning(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.planned.opacity(0.18), in: Capsule())
                            .foregroundStyle(Theme.planned)
                    }
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted.opacity(0.6))
        }
        .padding(16)
        .background(lastUsed ? Theme.controlOn : Theme.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(lastUsed ? Color.white.opacity(0.18) : Theme.panelBorder))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(region.name), \(savedRoutes) saved routes")
    }
}

#Preview {
    RegionPicker { _ in }
}
