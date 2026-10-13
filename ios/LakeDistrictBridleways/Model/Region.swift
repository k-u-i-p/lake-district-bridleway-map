import Foundation

/// The bounds a region's map is framed to and outlined with.
nonisolated struct FocusBounds: Sendable, Hashable {
    let south: Double, north: Double, west: Double, east: Double
}

/// A riding area. Each region bundles its own OpenStreetMap network (and, for the Lake District, the
/// built-in reference loop), frames and labels the map in its own way, and keeps its saved routes in
/// its own Core Data store. The region is chosen on the first screen.
nonisolated enum Region: String, CaseIterable, Identifiable, Sendable {
    case lakeDistrict = "lakes"
    case northYorkMoors = "nym"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .lakeDistrict: "Lake District"
        case .northYorkMoors: "North York Moors"
        }
    }

    /// The extent covered, as shown on the region picker.
    var extent: String {
        switch self {
        case .lakeDistrict: "Ennerdale to Haweswater, Bassenthwaite to Windermere"
        case .northYorkMoors: "Osmotherley to the coast, Guisborough to Helmsley"
        }
    }

    var systemImage: String {
        switch self {
        case .lakeDistrict: "mountain.2.fill"
        case .northYorkMoors: "leaf.fill"
        }
    }

    /// Title of the peaks overlay toggle: the ten highest summits in the bundled data.
    var peaksTitle: String {
        switch self {
        case .lakeDistrict: "Ten highest fells"
        case .northYorkMoors: "Ten highest tops"
        }
    }

    /// Bundled `network-<id>.json`, produced by `tools/build.sh <id>`.
    var networkResource: String { "network-\(rawValue)" }

    /// Bundled reference loop, if the region has one.
    var routeResource: String? {
        switch self {
        case .lakeDistrict: "route-lakes"
        case .northYorkMoors: nil
        }
    }

    /// File name of the region's Core Data store. The Lake District keeps the name the single-region
    /// app used, so routes saved before regions existed are still there.
    var storeFileName: String {
        switch self {
        case .lakeDistrict: "LakeDistrictBridleways.sqlite"
        case .northYorkMoors: "NorthYorkMoors.sqlite"
        }
    }

    var focus: FocusBounds {
        switch self {
        case .lakeDistrict: FocusBounds(south: 54.27, north: 54.69, west: -3.44, east: -2.74)
        case .northYorkMoors: FocusBounds(south: 54.21, north: 54.56, west: -1.33, east: -0.47)
        }
    }

    /// Valley, lake, moor and town labels drawn over the map.
    var labels: [MapLabel] {
        switch self {
        case .lakeDistrict: Self.lakeDistrictLabels
        case .northYorkMoors: Self.northYorkMoorsLabels
        }
    }

    private static let lakeDistrictLabels: [MapLabel] = [
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

    private static let northYorkMoorsLabels: [MapLabel] = [
        .init(text: "Cleveland Hills", coordinate: LatLon(54.445, -1.150), rotation: -40, small: false),
        .init(text: "Hambleton Hills", coordinate: LatLon(54.290, -1.240), rotation: -80, small: true),
        .init(text: "Bilsdale", coordinate: LatLon(54.370, -1.105), rotation: -80, small: false),
        .init(text: "Bransdale", coordinate: LatLon(54.330, -1.025), rotation: -80, small: false),
        .init(text: "Farndale", coordinate: LatLon(54.345, -0.960), rotation: -70, small: false),
        .init(text: "Rosedale", coordinate: LatLon(54.335, -0.890), rotation: -70, small: false),
        .init(text: "Westerdale", coordinate: LatLon(54.445, -0.985), rotation: -40, small: false),
        .init(text: "Eskdale", coordinate: LatLon(54.455, -0.780), rotation: 0, small: false),
        .init(text: "Glaisdale", coordinate: LatLon(54.405, -0.860), rotation: -60, small: true),
        .init(text: "Fylingdales Moor", coordinate: LatLon(54.375, -0.620), rotation: 0, small: false),
        .init(text: "Newtondale", coordinate: LatLon(54.345, -0.735), rotation: -80, small: true),
        .init(text: "Dalby Forest", coordinate: LatLon(54.275, -0.680), rotation: 0, small: false),
        .init(text: "Ryedale", coordinate: LatLon(54.280, -1.090), rotation: -50, small: true),
        .init(text: "Helmsley", coordinate: LatLon(54.246, -1.062), rotation: 0, small: true),
        .init(text: "Pickering", coordinate: LatLon(54.246, -0.778), rotation: 0, small: true),
        .init(text: "Kirkbymoorside", coordinate: LatLon(54.272, -0.932), rotation: 0, small: true),
        .init(text: "Hutton-le-Hole", coordinate: LatLon(54.293, -0.925), rotation: 0, small: true),
        .init(text: "Sutton Bank", coordinate: LatLon(54.239, -1.214), rotation: 0, small: true),
        .init(text: "Osmotherley", coordinate: LatLon(54.372, -1.299), rotation: 0, small: true),
        .init(text: "Stokesley", coordinate: LatLon(54.470, -1.192), rotation: 0, small: true),
        .init(text: "Great Ayton", coordinate: LatLon(54.490, -1.132), rotation: 0, small: true),
        .init(text: "Guisborough", coordinate: LatLon(54.536, -1.057), rotation: 0, small: true),
        .init(text: "Danby", coordinate: LatLon(54.468, -0.912), rotation: 0, small: true),
        .init(text: "Goathland", coordinate: LatLon(54.401, -0.722), rotation: 0, small: true),
        .init(text: "Whitby", coordinate: LatLon(54.486, -0.613), rotation: 0, small: true),
        .init(text: "Robin Hood's Bay", coordinate: LatLon(54.434, -0.536), rotation: 0, small: true),
    ]
}
