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
    case yorkshireDales = "dales"
    case cairngorms = "cairngorms"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .lakeDistrict: "Lake District"
        case .northYorkMoors: "North York Moors"
        case .yorkshireDales: "Yorkshire Dales"
        case .cairngorms: "Cairngorms"
        }
    }

    /// The extent covered, as shown on the region picker.
    var extent: String {
        switch self {
        case .lakeDistrict: "Ennerdale to Haweswater, Bassenthwaite to Windermere"
        case .northYorkMoors: "Osmotherley to the coast, Guisborough to Helmsley"
        case .yorkshireDales: "The Howgills to Nidderdale, Kirkby Stephen to Malham"
        case .cairngorms: "Newtonmore to Glen Tanar, Grantown to Blair Atholl"
        }
    }

    var systemImage: String {
        switch self {
        case .lakeDistrict: "mountain.2.fill"
        case .northYorkMoors: "leaf.fill"
        case .yorkshireDales: "water.waves"
        case .cairngorms: "snowflake"
        }
    }

    /// Title of the peaks overlay toggle: the ten highest summits in the bundled data.
    var peaksTitle: String {
        switch self {
        case .lakeDistrict, .yorkshireDales: "Ten highest fells"
        case .northYorkMoors: "Ten highest tops"
        case .cairngorms: "Ten highest Munros"
        }
    }

    /// Layers shown until the rider picks their own. The Cairngorms has no bridleways (Scottish
    /// access rights cover tracks instead), so it opens on its tracks.
    var defaultLayers: Set<String> {
        switch self {
        case .lakeDistrict, .northYorkMoors, .yorkshireDales: ["bridleway"]
        case .cairngorms: ["track"]
        }
    }

    /// UserDefaults key for the layers shown. The English regions share one choice, under the key
    /// the single-region app used; the Cairngorms, with its different rights of way, keeps its own.
    var visibleLayersKey: String {
        switch self {
        case .lakeDistrict, .northYorkMoors, .yorkshireDales: "visibleLayers"
        case .cairngorms: "visibleLayers-cairngorms"
        }
    }

    /// The access caveat under the planner card.
    var accessNote: String {
        switch self {
        case .lakeDistrict, .northYorkMoors, .yorkshireDales:
            "Cycling on a public footpath is not a right of way in England; check the definitive map before relying on a right of way."
        case .cairngorms:
            "Scottish access rights cover cycling on most tracks and paths if you ride responsibly; follow the Scottish Outdoor Access Code."
        }
    }

    /// Bundled `network-<id>.json`, produced by `tools/build.sh <id>`.
    var networkResource: String { "network-\(rawValue)" }

    /// Bundled reference loop, if the region has one.
    var routeResource: String? {
        switch self {
        case .lakeDistrict: "route-lakes"
        case .northYorkMoors, .yorkshireDales, .cairngorms: nil
        }
    }

    /// File name of the region's Core Data store. The Lake District keeps the name the single-region
    /// app used, so routes saved before regions existed are still there.
    var storeFileName: String {
        switch self {
        case .lakeDistrict: "LakeDistrictBridleways.sqlite"
        case .northYorkMoors: "NorthYorkMoors.sqlite"
        case .yorkshireDales: "YorkshireDales.sqlite"
        case .cairngorms: "Cairngorms.sqlite"
        }
    }

    var focus: FocusBounds {
        switch self {
        case .lakeDistrict: FocusBounds(south: 54.27, north: 54.69, west: -3.44, east: -2.74)
        case .northYorkMoors: FocusBounds(south: 54.21, north: 54.56, west: -1.33, east: -0.47)
        case .yorkshireDales: FocusBounds(south: 54.02, north: 54.46, west: -2.58, east: -1.80)
        case .cairngorms: FocusBounds(south: 56.76, north: 57.34, west: -4.15, east: -2.85)
        }
    }

    /// Valley, lake, moor and town labels drawn over the map.
    var labels: [MapLabel] {
        switch self {
        case .lakeDistrict: Self.lakeDistrictLabels
        case .northYorkMoors: Self.northYorkMoorsLabels
        case .yorkshireDales: Self.yorkshireDalesLabels
        case .cairngorms: Self.cairngormsLabels
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

    private static let yorkshireDalesLabels: [MapLabel] = [
        .init(text: "Swaledale", coordinate: LatLon(54.390, -2.140), rotation: 10, small: false),
        .init(text: "Arkengarthdale", coordinate: LatLon(54.452, -2.000), rotation: -50, small: true),
        .init(text: "Wensleydale", coordinate: LatLon(54.285, -1.930), rotation: 5, small: false),
        .init(text: "Wharfedale", coordinate: LatLon(54.000, -1.905), rotation: 55, small: false),
        .init(text: "Littondale", coordinate: LatLon(54.125, -2.130), rotation: 45, small: true),
        .init(text: "Ribblesdale", coordinate: LatLon(54.168, -2.305), rotation: 55, small: false),
        .init(text: "Dentdale", coordinate: LatLon(54.278, -2.405), rotation: -10, small: false),
        .init(text: "Garsdale", coordinate: LatLon(54.322, -2.350), rotation: -20, small: true),
        .init(text: "Mallerstang", coordinate: LatLon(54.395, -2.335), rotation: -80, small: true),
        .init(text: "Howgill Fells", coordinate: LatLon(54.395, -2.500), rotation: 0, small: false),
        .init(text: "Coverdale", coordinate: LatLon(54.235, -1.930), rotation: -35, small: true),
        .init(text: "Bishopdale", coordinate: LatLon(54.245, -2.040), rotation: -50, small: true),
        .init(text: "Nidderdale", coordinate: LatLon(54.125, -1.815), rotation: 60, small: false),
        .init(text: "Hawes", coordinate: LatLon(54.304, -2.197), rotation: 0, small: true),
        .init(text: "Askrigg", coordinate: LatLon(54.313, -2.078), rotation: 0, small: true),
        .init(text: "Leyburn", coordinate: LatLon(54.309, -1.828), rotation: 0, small: true),
        .init(text: "Reeth", coordinate: LatLon(54.388, -1.943), rotation: 0, small: true),
        .init(text: "Kirkby Stephen", coordinate: LatLon(54.472, -2.349), rotation: 0, small: true),
        .init(text: "Sedbergh", coordinate: LatLon(54.323, -2.528), rotation: 0, small: true),
        .init(text: "Ingleton", coordinate: LatLon(54.154, -2.468), rotation: 0, small: true),
        .init(text: "Settle", coordinate: LatLon(54.068, -2.278), rotation: 0, small: true),
        .init(text: "Malham", coordinate: LatLon(54.061, -2.152), rotation: 0, small: true),
        .init(text: "Kettlewell", coordinate: LatLon(54.147, -2.047), rotation: 0, small: true),
        .init(text: "Grassington", coordinate: LatLon(54.071, -1.998), rotation: 0, small: true),
        .init(text: "Pateley Bridge", coordinate: LatLon(54.086, -1.758), rotation: 0, small: true),
    ]

    private static let cairngormsLabels: [MapLabel] = [
        .init(text: "Strathspey", coordinate: LatLon(57.160, -3.880), rotation: -40, small: false),
        .init(text: "Glen Feshie", coordinate: LatLon(57.050, -3.850), rotation: 63, small: false),
        .init(text: "Rothiemurchus", coordinate: LatLon(57.150, -3.785), rotation: 0, small: true),
        .init(text: "Glenmore", coordinate: LatLon(57.168, -3.700), rotation: -10, small: true),
        .init(text: "Lairig Ghru", coordinate: LatLon(57.090, -3.700), rotation: 80, small: true),
        .init(text: "Glen Derry", coordinate: LatLon(57.050, -3.592), rotation: 85, small: true),
        .init(text: "Glen Avon", coordinate: LatLon(57.128, -3.480), rotation: -8, small: true),
        .init(text: "Deeside", coordinate: LatLon(57.025, -3.290), rotation: -12, small: false),
        .init(text: "Glen Clunie", coordinate: LatLon(56.940, -3.395), rotation: 85, small: true),
        .init(text: "Glen Muick", coordinate: LatLon(56.990, -3.110), rotation: -55, small: true),
        .init(text: "Glen Tanar", coordinate: LatLon(57.026, -2.913), rotation: -38, small: true),
        .init(text: "Strathdon", coordinate: LatLon(57.190, -3.110), rotation: 0, small: false),
        .init(text: "Glen Tilt", coordinate: LatLon(56.833, -3.758), rotation: -50, small: false),
        .init(text: "Glen Clova", coordinate: LatLon(56.840, -3.130), rotation: 47, small: true),
        .init(text: "Aviemore", coordinate: LatLon(57.194, -3.829), rotation: 0, small: true),
        .init(text: "Kingussie", coordinate: LatLon(57.080, -4.051), rotation: 0, small: true),
        .init(text: "Newtonmore", coordinate: LatLon(57.066, -4.119), rotation: 0, small: true),
        .init(text: "Kincraig", coordinate: LatLon(57.127, -3.931), rotation: 0, small: true),
        .init(text: "Carrbridge", coordinate: LatLon(57.283, -3.815), rotation: 0, small: true),
        .init(text: "Boat of Garten", coordinate: LatLon(57.249, -3.754), rotation: 0, small: true),
        .init(text: "Nethy Bridge", coordinate: LatLon(57.265, -3.658), rotation: 0, small: true),
        .init(text: "Grantown-on-Spey", coordinate: LatLon(57.330, -3.610), rotation: 0, small: true),
        .init(text: "Tomintoul", coordinate: LatLon(57.252, -3.379), rotation: 0, small: true),
        .init(text: "Braemar", coordinate: LatLon(57.006, -3.400), rotation: 0, small: true),
        .init(text: "Ballater", coordinate: LatLon(57.050, -3.041), rotation: 0, small: true),
        .init(text: "Dinnet", coordinate: LatLon(57.077, -2.893), rotation: 0, small: true),
        .init(text: "Spittal of Glenshee", coordinate: LatLon(56.813, -3.461), rotation: 0, small: true),
        .init(text: "Blair Atholl", coordinate: LatLon(56.766, -3.848), rotation: 0, small: true),
    ]
}
