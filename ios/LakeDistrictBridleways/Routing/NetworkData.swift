import Foundation

/// One OpenStreetMap way from the bundled network file.
nonisolated struct Way: Sendable {
    let category: Int8          // index into NetworkData.categories
    let length: Int32           // metres
    let osmID: Int64
    let encoded: String         // encoded polyline, precision 5
    let name: String?
    let prowRef: String?
    let surface: String?
    let tracktype: String?
    let highway: String?
}

nonisolated struct Peak: Sendable, Identifiable {
    let name: String
    let elevation: Int
    let coordinate: LatLon
    var id: String { name }
}

/// The compact dataset produced by `tools/convert.py` (`network.json`).
nonisolated struct NetworkData: Sendable {
    let categories: [String]
    let ways: [Way]
    let peaks: [Peak]

    enum LoadError: Error { case missing, malformed }

    /// Loads a region's `network-<id>.json` from the app bundle.
    static func loadBundled(resource: String) throws -> NetworkData {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else { throw LoadError.missing }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> NetworkData {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cats = root["cats"] as? [String],
              let rawWays = root["ways"] as? [[Any]] else { throw LoadError.malformed }
        var ways: [Way] = []
        ways.reserveCapacity(rawWays.count)
        for r in rawWays {
            guard r.count >= 4,
                  let cat = r[0] as? Int, let len = r[1] as? Int,
                  let id = (r[2] as? NSNumber)?.int64Value,
                  let enc = r[3] as? String else { throw LoadError.malformed }
            let extra = r.count > 4 ? r[4] as? [String: Any] : nil
            ways.append(Way(category: Int8(cat), length: Int32(len), osmID: id, encoded: enc,
                            name: extra?["name"] as? String,
                            prowRef: extra?["prow_ref"] as? String,
                            surface: extra?["surface"] as? String,
                            tracktype: extra?["tracktype"] as? String,
                            highway: extra?["hw"] as? String))
        }
        var peaks: [Peak] = []
        for p in (root["peaks"] as? [[String: Any]]) ?? [] {
            guard let n = p["n"] as? String, let e = p["e"] as? Int,
                  let la = p["la"] as? Double, let lo = p["lo"] as? Double else { continue }
            peaks.append(Peak(name: n, elevation: e, coordinate: LatLon(la, lo)))
        }
        return NetworkData(categories: cats, ways: ways, peaks: peaks)
    }
}

/// A route with its summary statistics: the bundled reference loop, or a planned loop that has been
/// given elevation data.
nonisolated struct RouteSummary: Sendable, Identifiable {
    /// The fixed id of the bundled reference loop, so the planner can remember it was open.
    static let referenceID = UUID(uuidString: "7D1C2B6E-5A40-4F3E-9C8B-0F2E5A7B9D11")!

    let id: UUID
    var name: String
    var coords: [LatLon]
    var length: Double           // metres
    var ascent: Int?             // metres, nil when unknown
    var profile: [Double]?       // elevation samples along the route
    var byCategory: [String: Double]

    init(id: UUID = UUID(), name: String, coords: [LatLon], length: Double, ascent: Int?, profile: [Double]?, byCategory: [String: Double] = [:]) {
        self.id = id
        self.name = name
        self.coords = coords
        self.length = length
        self.ascent = ascent
        self.profile = profile
        self.byCategory = byCategory
    }

    /// Loads a region's bundled reference loop (`route-lakes.json`, the loop reconstructed from the
    /// reference image by `tools/make-route.js`). Nil for regions without one.
    static func loadBundledReference(resource: String?) -> RouteSummary? {
        guard let resource,
              let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = root["name"] as? String,
              let len = root["len"] as? Double,
              let raw = root["coords"] as? [[Double]] else { return nil }
        let coords = raw.compactMap { $0.count == 2 ? LatLon($0[0], $0[1]) : nil }
        let asc = root["asc"] as? Int
        let profile = root["profile"] as? [Double]
        let byCat = (root["byCat"] as? [String: Double]) ?? [:]
        return RouteSummary(id: referenceID, name: name, coords: coords, length: len, ascent: asc, profile: profile, byCategory: byCat)
    }
}
