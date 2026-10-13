import SwiftUI

/// A toggleable rights-of-way layer on the map. Mirrors `CATS` in the web app.
nonisolated struct DisplayLayer: Identifiable, Sendable, Hashable {
    let key: String
    let name: String
    let colorHex: UInt32
    let dashed: Bool
    let thin: Bool
    let categories: [String]   // network categories drawn by this layer
    let defaultOn: Bool

    var id: String { key }
    var color: Color { Color(hex: colorHex) }

    static let all: [DisplayLayer] = [
        DisplayLayer(key: "bridleway", name: "Public bridleway", colorHex: 0x3ddc84, dashed: false, thin: false, categories: ["bridleway"], defaultOn: true),
        DisplayLayer(key: "boat", name: "Byway open to all traffic", colorHex: 0xff9f1a, dashed: false, thin: false, categories: ["boat"], defaultOn: false),
        DisplayLayer(key: "restricted", name: "Restricted byway", colorHex: 0xb388ff, dashed: false, thin: false, categories: ["restricted"], defaultOn: false),
        DisplayLayer(key: "permissive", name: "Permissive bridleway", colorHex: 0x4fd1ff, dashed: true, thin: false, categories: ["permissive"], defaultOn: false),
        DisplayLayer(key: "other", name: "Bridleway (undesignated)", colorHex: 0xffffff, dashed: true, thin: false, categories: ["other"], defaultOn: false),
        DisplayLayer(key: "footpath", name: "Public footpath", colorHex: 0xff6b9d, dashed: true, thin: true, categories: ["footpath"], defaultOn: false),
        DisplayLayer(key: "path", name: "Other paths & cycleways", colorHex: 0xe8d5a3, dashed: true, thin: true, categories: ["path", "cycleway"], defaultOn: false),
    ]

    static func layer(forCategory c: String) -> DisplayLayer? {
        all.first { $0.categories.contains(c) }
    }

    /// Human name for a network category (cycleways share the "path" layer but keep their own name).
    static func displayName(forCategory c: String) -> String {
        switch c {
        case "cycleway": return "Cycleway"
        case "track": return "Track"
        case "road_minor": return "Minor road"
        case "road_major": return "Main road"
        case "trunk": return "Trunk road"
        case "ferry": return "Ferry"
        default: return layer(forCategory: c)?.name ?? c.capitalized
        }
    }
}

/// Groups used for the planned-loop distance breakdown. Mirrors `GROUPS` in the web app.
nonisolated struct BreakdownGroup: Identifiable, Sendable {
    let name: String
    let shortName: String
    let categories: [String]
    let colorHex: UInt32
    var id: String { name }
    var color: Color { Color(hex: colorHex) }

    static let all: [BreakdownGroup] = [
        BreakdownGroup(name: "Bridleways & byways", shortName: "Bridleways", categories: ["bridleway", "boat", "restricted", "permissive", "other"], colorHex: 0x3ddc84),
        BreakdownGroup(name: "Cycleways & tracks", shortName: "Tracks", categories: ["cycleway", "track"], colorHex: 0xe8d5a3),
        BreakdownGroup(name: "Footpaths", shortName: "Footpaths", categories: ["footpath", "path"], colorHex: 0xff6b9d),
        BreakdownGroup(name: "Roads", shortName: "Roads", categories: ["road_minor", "road_major", "trunk"], colorHex: 0x9aa3ad),
        BreakdownGroup(name: "Ferry", shortName: "Ferry", categories: ["ferry"], colorHex: 0x4fd1ff),
    ]

    func metres(in byCategory: [String: Double]) -> Double {
        categories.reduce(0) { $0 + (byCategory[$1] ?? 0) }
    }
}

/// Base map choices. Satellite and Standard use Apple's map; the rest are raster tile servers, as in the web app.
nonisolated enum BaseMap: String, CaseIterable, Identifiable, Sendable {
    case satellite = "Satellite"
    case topo = "Topo"
    case cycle = "Cycle"
    case osm = "OSM"
    case standard = "Apple"

    var id: String { rawValue }

    /// Tile URL template, or nil for Apple-rendered maps.
    var tileTemplate: String? {
        switch self {
        case .satellite, .standard: return nil
        case .topo: return "https://tile.opentopomap.org/{z}/{x}/{y}.png"
        case .cycle: return "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png"
        case .osm: return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        }
    }

    var maximumZoom: Int {
        switch self {
        case .topo: return 17
        case .cycle: return 18
        case .osm: return 19
        default: return 20
        }
    }

    var attribution: String {
        switch self {
        case .satellite, .standard: return "Map data © Apple"
        case .topo: return "© OpenStreetMap contributors, SRTM | © OpenTopoMap (CC-BY-SA)"
        case .cycle: return "© OpenStreetMap contributors | CyclOSM"
        case .osm: return "© OpenStreetMap contributors"
        }
    }
}

/// Valley, lake and town labels drawn over the map, with a rotation in degrees.
nonisolated struct MapLabel: Identifiable, Sendable {
    let text: String
    let coordinate: LatLon
    let rotation: Double
    let small: Bool
    var id: String { text }

    static let all: [MapLabel] = [
        .init(text: "Bassenthwaite", coordinate: LatLon(54.650, -3.215), rotation: -62, small: false),
        .init(text: "Buttermere", coordinate: LatLon(54.542, -3.280), rotation: -40, small: false),
        .init(text: "Ennerdale", coordinate: LatLon(54.522, -3.385), rotation: 0, small: false),
        .init(text: "Borrowdale", coordinate: LatLon(54.515, -3.150), rotation: 80, small: false),
        .init(text: "Thirlmere", coordinate: LatLon(54.535, -3.065), rotation: 60, small: false),
        .init(text: "Ullswater", coordinate: LatLon(54.580, -2.885), rotation: -30, small: false),
        .init(text: "Haweswater", coordinate: LatLon(54.515, -2.800), rotation: -60, small: false),
        .init(text: "Langdale", coordinate: LatLon(54.445, -3.090), rotation: 0, small: false),
        .init(text: "Eskdale", coordinate: LatLon(54.395, -3.275), rotation: -45, small: false),
        .init(text: "Wast Water", coordinate: LatLon(54.440, -3.300), rotation: -35, small: true),
        .init(text: "Windermere", coordinate: LatLon(54.335, -2.930), rotation: -65, small: false),
        .init(text: "Coniston", coordinate: LatLon(54.335, -3.072), rotation: -80, small: false),
        .init(text: "Duddon", coordinate: LatLon(54.335, -3.200), rotation: -70, small: false),
        .init(text: "Keswick", coordinate: LatLon(54.601, -3.137), rotation: 0, small: true),
        .init(text: "Ambleside", coordinate: LatLon(54.428, -2.962), rotation: 0, small: true),
        .init(text: "Grasmere", coordinate: LatLon(54.459, -3.025), rotation: 0, small: true),
        .init(text: "Kentmere", coordinate: LatLon(54.430, -2.845), rotation: -80, small: true),
        .init(text: "Shap", coordinate: LatLon(54.531, -2.676), rotation: 0, small: true),
    ]
}

/// The focus area: Ennerdale to Haweswater, Bassenthwaite to Windermere.
nonisolated enum FocusArea {
    static let south = 54.27, north = 54.69, west = -3.44, east = -2.74
}

nonisolated enum Theme {
    static let accent = Color(hex: 0xe41b23)
    static let panel = Color(red: 12 / 255, green: 14 / 255, blue: 18 / 255)
    static let panelBorder = Color.white.opacity(0.08)
    static let muted = Color(hex: 0x9aa3ad)
    static let control = Color(hex: 0x1b1f26)
    static let controlOn = Color(hex: 0x2b303a)
    static let planned = Color(hex: 0xffd400)
    static let reference = Color(hex: 0xe41b23)
}

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

nonisolated enum Format {
    static func km(_ metres: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f km", metres / 1000)
    }
    /// Metres with thousands grouping, e.g. "3,715 m".
    static func metres(_ m: Int) -> String {
        m.formatted(.number.grouping(.automatic)) + " m"
    }
    static func kmShort(_ metres: Double) -> String {
        metres < 10_000 ? String(format: "%.2f km", metres / 1000) : String(format: "%.1f km", metres / 1000)
    }
}
