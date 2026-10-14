import Foundation

/// The summit card for one of a region's ten peaks: a photo, a line about the summit and the usual
/// routes up. Bundled as `peaks-<region>.json`, built from `tools/peaks.json` by `tools/peaks.py`.
nonisolated struct PeakDetails: Decodable, Sendable {
    struct Route: Decodable, Sendable, Identifiable {
        let name: String
        let text: String
        /// One way to the summit, where the route has a usual start.
        let km: Double?
        let ascent: Int?
        var id: String { name }
    }

    /// Asset catalogue image, `peak-<region>-<slug>`.
    let photo: String
    /// Photographer and licence, from Wikimedia Commons.
    let credit: String
    /// The photo's Commons page.
    let source: URL
    let about: String
    let routes: [Route]
    let wiki: URL?

    /// Loads a region's summit cards, keyed by peak name. Empty if the region has none.
    static func loadBundled(resource: String) -> [String: PeakDetails] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let details = try? JSONDecoder().decode([String: PeakDetails].self, from: data) else { return [:] }
        return details
    }
}

/// The nearest way a rider can use to reach a summit: a bridleway or byway in England, a track in Scotland.
nonisolated struct NearestRide: Sendable {
    let distance: Double   // metres from the summit
    let name: String?
    let category: String
}

/// Shown when a peak on the map is tapped.
struct PeakInfo: Identifiable, Sendable {
    let peak: Peak
    /// 1 for the highest of the region's ten peaks.
    let rank: Int
    let details: PeakDetails?
    /// Nil when there is none within reach.
    let nearestRide: NearestRide?
    var id: String { peak.id }
}
