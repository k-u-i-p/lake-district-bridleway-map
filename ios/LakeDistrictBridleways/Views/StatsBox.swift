import SwiftUI

/// The black "sticker" with distance, climb and an elevation profile, like the web app's stats box.
struct StatsBox: View {
    let stats: Stats
    /// Fixed width for the floating iPad sticker; nil fills the panel width.
    var fixedWidth: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stats.title.uppercased())
                .font(.system(size: 11, weight: .medium).width(.condensed))
                .kerning(1.4)
                .foregroundStyle(Color(white: 0.67))
                .lineLimit(1)
            if let profile = stats.profile, profile.count > 1 {
                ElevationProfile(elevations: profile)
                    .frame(height: 64)
                    .padding(.vertical, 4)
            }
            statRow("Distance:", Format.km(stats.length))
            statRow("Elevation:", stats.ascent.map { "\($0) m" } ?? "–")
        }
        .padding(EdgeInsets(top: 14, leading: 18, bottom: 12, trailing: 18))
        .frame(width: fixedWidth, alignment: .leading)
        .background(Color.black)
        .clipShape(StickerShape())
        .foregroundStyle(.white)
        .rotationEffect(.degrees(-0.6))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased())
            Spacer(minLength: 24)
            Text(value.uppercased()).monospacedDigit()
        }
        .font(.system(size: 17, weight: .semibold).width(.condensed))
        .kerning(0.7)
    }
}

/// Slightly skewed sticker outline, matching the web app's clip-path.
nonisolated struct StickerShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.01, y: r.minY + r.height * 0.03))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.99, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.96))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.02, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// White line chart of elevation along the route with a simple axis.
struct ElevationProfile: View {
    let elevations: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let mn = elevations.min() ?? 0, mx = elevations.max() ?? 0
            let range = max(mx - mn, 50)
            Path { p in
                p.move(to: CGPoint(x: 4, y: 4))
                p.addLine(to: CGPoint(x: 4, y: h - 3))
                p.addLine(to: CGPoint(x: w - 4, y: h - 3))
            }
            .stroke(.white, lineWidth: 1.5)
            Path { p in
                for (i, e) in elevations.enumerated() {
                    let x = 4 + (w - 8) * CGFloat(i) / CGFloat(elevations.count - 1)
                    let y = h - 4 - (h - 8) * CGFloat((e - mn) / range)
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}

#Preview {
    StatsBox(stats: Stats(title: "Loop from the image", length: 207_173, ascent: 9_331, profile: (0..<120).map { 200 + 400 * abs(sin(Double($0) / 9)) }))
        .padding(40)
        .background(Color.gray)
}
