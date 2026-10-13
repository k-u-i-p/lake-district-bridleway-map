import SwiftUI

/// Filled line chart of elevation along the route, with the min and max heights labelled.
struct ElevationProfile: View {
    let elevations: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let mn = elevations.min() ?? 0, mx = elevations.max() ?? 0
            let range = max(mx - mn, 50)
            let top: CGFloat = 12, bottom: CGFloat = 2
            let points = elevations.enumerated().map { i, e in
                CGPoint(x: w * CGFloat(i) / CGFloat(elevations.count - 1),
                        y: h - bottom - (h - bottom - top) * CGFloat((e - mn) / range))
            }
            let line = Path { p in
                for (i, pt) in points.enumerated() { i == 0 ? p.move(to: pt) : p.addLine(to: pt) }
            }
            let fill = Path { p in
                p.move(to: CGPoint(x: 0, y: h))
                for pt in points { p.addLine(to: pt) }
                p.addLine(to: CGPoint(x: w, y: h))
                p.closeSubpath()
            }
            fill.fill(LinearGradient(colors: [Theme.planned.opacity(0.45), Theme.planned.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            line.stroke(Theme.planned, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            Text("\(Int(mx)) m")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                .position(x: w - 18, y: 6)
            Text("\(Int(mn)) m")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                .position(x: 18, y: h - 8)
        }
    }
}

/// Stacked bar of the planned loop's distance by surface group, with a legend.
struct RouteMix: View {
    let byCategory: [String: Double]
    let total: Double

    private var parts: [(BreakdownGroup, Double)] {
        BreakdownGroup.all.compactMap { g in
            let m = g.metres(in: byCategory)
            return m > 0 ? (g, m) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SURFACE").sectionTitleStyle()
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0.id) { group, m in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(group.color)
                            .frame(width: max(3, (geo.size.width - CGFloat(parts.count - 1) * 2) * CGFloat(m / max(total, 1))))
                    }
                }
            }
            .frame(height: 8)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 5) {
                ForEach(parts, id: \.0.id) { group, m in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(group.color).frame(width: 9, height: 9)
                        Text(group.shortName).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Format.km(m)).monospacedDigit().foregroundStyle(.white)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(12)
        .background(Theme.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    VStack {
        ElevationProfile(elevations: (0..<120).map { 200 + 400 * abs(sin(Double($0) / 9)) }).frame(height: 72)
        RouteMix(byCategory: ["bridleway": 20_000, "footpath": 3000, "road_minor": 5000], total: 28_000)
    }
    .padding()
    .background(Theme.panel)
}
