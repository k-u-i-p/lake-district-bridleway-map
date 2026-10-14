import SwiftUI

/// The summit card for a tapped peak: a photo, its height, a line about it, the usual routes up and
/// how far the nearest bridleway (or track, in Scotland) is from the top.
struct PeakDetailSheet: View {
    let info: PeakInfo
    let region: Region
    @Environment(\.dismiss) private var dismiss

    private var feet: Int { Int((Double(info.peak.elevation) * 3.28084).rounded()) }

    private var rankText: String {
        info.rank == 1 ? "Highest in the region" : "\(info.rank)\(ordinalSuffix(info.rank)) highest in the region"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    hero
                        .listRowInsets(EdgeInsets())
                } footer: {
                    if let d = info.details {
                        Text("Photo: \(d.credit)").font(.caption2)
                    }
                }
                if let d = info.details, !d.about.isEmpty {
                    Section {
                        Text(d.about).font(.callout).lineSpacing(2)
                    }
                }
                if let routes = info.details?.routes, !routes.isEmpty {
                    Section("Routes up") {
                        ForEach(routes) { route in routeRow(route) }
                    }
                }
                Section {
                    rideRow
                } footer: {
                    Text(region.accessNote)
                }
                Section {
                    if let wiki = info.details?.wiki {
                        Link(destination: wiki) { Label("Wikipedia", systemImage: "book") }
                    }
                    if let source = info.details?.source {
                        Link(destination: source) { Label("Photo on Wikimedia Commons", systemImage: "photo") }
                    }
                }
            }
            .navigationTitle("Summit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// Photo with the name, height and rank laid over it, as on the region cards.
    private var hero: some View {
        Color.clear
            .frame(height: 210)
            .overlay {
                if let photo = info.details?.photo {
                    Image(photo).resizable().scaledToFill().accessibilityHidden(true)
                } else {
                    Theme.control
                }
            }
            .clipped()
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.peak.name)
                        .font(.system(size: 24, weight: .bold))
                    HStack(spacing: 8) {
                        Text("\(Format.metres(info.peak.elevation)) · \(feet.formatted()) ft")
                            .font(.system(size: 15, weight: .semibold).width(.condensed))
                        Text(rankText.uppercased())
                            .font(.system(size: 9, weight: .bold)).kerning(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.5), in: Capsule())
                            .foregroundStyle(Theme.planned)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
    }

    private func routeRow(_ route: PeakDetails.Route) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(route.name).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                if let stats = stats(route) {
                    Text(stats)
                        .font(.system(size: 13, weight: .medium).width(.condensed))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            Text(route.text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    /// "About 4.5 km · 900 m up", one way to the summit.
    private func stats(_ route: PeakDetails.Route) -> String? {
        var parts: [String] = []
        if let km = route.km { parts.append(km.formatted(.number.precision(.fractionLength(0...1))) + " km") }
        if let up = route.ascent { parts.append("\(Format.metres(up)) up") }
        return parts.isEmpty ? nil : "≈ " + parts.joined(separator: " · ")
    }

    private var rideRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nearest \(region.rideName)")
                if let ride = info.nearestRide {
                    Text([ride.name, DisplayLayer.displayName(forCategory: ride.category)].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let ride = info.nearestRide {
                Text(ride.distance < 50 ? "At the summit" : Format.distance(ride.distance))
                    .foregroundStyle(ride.distance < 50 ? DisplayLayer.layer(forCategory: ride.category)?.color ?? .primary : .primary)
            } else {
                Text("Over 6 km").foregroundStyle(.secondary)
            }
        }
    }

    private func ordinalSuffix(_ n: Int) -> String {
        switch (n % 100, n % 10) {
        case (11...13, _): "th"
        case (_, 1): "st"
        case (_, 2): "nd"
        case (_, 3): "rd"
        default: "th"
        }
    }
}
