import Foundation

/// A snapped position on the network: the nearest graph node to a tapped point.
nonisolated struct Snap: Sendable, Hashable {
    let node: Int32
    let distance: Double
    let coordinate: LatLon
}

/// Routing graph built from `NetworkData`: deduplicated nodes, a compressed adjacency list of
/// directed edges (stored in forward/reverse pairs so `e ^ 1` is the reverse of edge `e`) and a
/// spatial grid for snapping. Immutable once built, so it is safe to share between tasks.
nonisolated final class RouteGraph: Sendable {
    let categories: [String]
    let ways: [Way]
    let nodeLat: [Int32]        // 1e-5 degree units
    let nodeLon: [Int32]
    let edgeTo: [Int32]
    let edgeLength: [Float]
    let edgeWay: [Int32]
    let offsets: [Int32]        // CSR offsets into `adjacent`, count = nodes + 1
    let adjacent: [Int32]       // edge indices
    let wayCategory: [Int8]
    let wayNodeOffsets: [Int32] // CSR offsets into `wayNodes`
    let wayNodes: [Int32]
    let grid: [Int64: [Int32]]  // cell key -> node indices
    let snapPreference: [Double]

    static let cell: Int32 = 500 // 0.005 degrees in 1e-5 units

    var nodeCount: Int { nodeLat.count }
    var edgeCount: Int { edgeTo.count }

    func coordinate(of node: Int32) -> LatLon {
        LatLon(Double(nodeLat[Int(node)]) / 1e5, Double(nodeLon[Int(node)]) / 1e5)
    }

    func coordinates(ofWay w: Int) -> [LatLon] {
        let lo = Int(wayNodeOffsets[w]), hi = Int(wayNodeOffsets[w + 1])
        return (lo..<hi).map { coordinate(of: wayNodes[$0]) }
    }

    func categoryIndex(_ name: String) -> Int8? {
        categories.firstIndex(of: name).map(Int8.init)
    }

    // MARK: - Build

    static func build(_ data: NetworkData) -> RouteGraph {
        let ways = data.ways
        var key2id: [Int64: Int32] = [:]
        key2id.reserveCapacity(ways.count * 6)
        var nlat: [Int32] = [], nlon: [Int32] = []
        nlat.reserveCapacity(ways.count * 6); nlon.reserveCapacity(ways.count * 6)
        var eFrom: [Int32] = [], eTo: [Int32] = [], eLen: [Float] = [], eWay: [Int32] = []
        var wayCat: [Int8] = []; wayCat.reserveCapacity(ways.count)
        var wayNodeOff: [Int32] = [0]; wayNodeOff.reserveCapacity(ways.count + 1)
        var wayNodes: [Int32] = []; wayNodes.reserveCapacity(ways.count * 6)

        @inline(__always) func nodeId(_ la: Int32, _ lo: Int32) -> Int32 {
            let k = Int64(la) * 100_000_000 + (Int64(lo) + 50_000_000)
            if let id = key2id[k] { return id }
            let id = Int32(nlat.count)
            key2id[k] = id
            nlat.append(la); nlon.append(lo)
            return id
        }

        for (w, way) in ways.enumerated() {
            let pts = Polyline.decode(way.encoded)
            let count = pts.count / 2
            var ids = [Int32](repeating: 0, count: count)
            for i in 0..<count { ids[i] = nodeId(pts[2 * i], pts[2 * i + 1]) }
            wayCat.append(way.category)
            wayNodes.append(contentsOf: ids)
            wayNodeOff.append(Int32(wayNodes.count))
            if count > 1 {
                for i in 0..<(count - 1) {
                    let a = ids[i], b = ids[i + 1]
                    if a == b { continue }
                    let len = Float(Geo.haversine(Double(nlat[Int(a)]) / 1e5, Double(nlon[Int(a)]) / 1e5,
                                                  Double(nlat[Int(b)]) / 1e5, Double(nlon[Int(b)]) / 1e5))
                    eFrom.append(a); eTo.append(b); eLen.append(len); eWay.append(Int32(w))
                    eFrom.append(b); eTo.append(a); eLen.append(len); eWay.append(Int32(w))
                }
            }
        }

        let n = nlat.count, m = eFrom.count
        var off = [Int32](repeating: 0, count: n + 1)
        for e in 0..<m { off[Int(eFrom[e]) + 1] += 1 }
        for i in 0..<n { off[i + 1] += off[i] }
        var adj = [Int32](repeating: 0, count: m)
        var fill = Array(off[0..<n])
        for e in 0..<m {
            let f = Int(eFrom[e])
            adj[Int(fill[f])] = Int32(e)
            fill[f] += 1
        }

        var grid: [Int64: [Int32]] = [:]
        grid.reserveCapacity(16_000)
        for i in 0..<n {
            grid[gridKey(nlat[i], nlon[i]), default: []].append(Int32(i))
        }

        // Prefer snapping to rideable ways: a footpath node must be much closer than a bridleway node to win.
        let prefTable: [String: Double] = ["footpath": 2.2, "path": 2.2, "ferry": 3, "trunk": 2, "track": 1.2, "cycleway": 1.1]
        let pref = data.categories.map { prefTable[$0] ?? 1 }

        return RouteGraph(categories: data.categories, ways: ways, nodeLat: nlat, nodeLon: nlon,
                          edgeTo: eTo, edgeLength: eLen, edgeWay: eWay, offsets: off, adjacent: adj,
                          wayCategory: wayCat, wayNodeOffsets: wayNodeOff, wayNodes: wayNodes,
                          grid: grid, snapPreference: pref)
    }

    private init(categories: [String], ways: [Way], nodeLat: [Int32], nodeLon: [Int32], edgeTo: [Int32],
                 edgeLength: [Float], edgeWay: [Int32], offsets: [Int32], adjacent: [Int32], wayCategory: [Int8],
                 wayNodeOffsets: [Int32], wayNodes: [Int32], grid: [Int64: [Int32]], snapPreference: [Double]) {
        self.categories = categories; self.ways = ways; self.nodeLat = nodeLat; self.nodeLon = nodeLon
        self.edgeTo = edgeTo; self.edgeLength = edgeLength; self.edgeWay = edgeWay; self.offsets = offsets
        self.adjacent = adjacent; self.wayCategory = wayCategory; self.wayNodeOffsets = wayNodeOffsets
        self.wayNodes = wayNodes; self.grid = grid; self.snapPreference = snapPreference
    }

    // MARK: - Spatial lookups

    @inline(__always) private static func floorDiv(_ a: Int32, _ b: Int32) -> Int64 {
        let q = Int64(a) / Int64(b)
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    @inline(__always) private static func gridKey(_ la: Int32, _ lo: Int32) -> Int64 {
        floorDiv(la, cell) * 100_000 + floorDiv(lo, cell)
    }

    /// Nearest node within `maxMetres`, weighted so footpaths and roads only win when much closer.
    func nearest(to p: LatLon, maxMetres: Double = 300) -> Snap? {
        let la = Int32((p.lat * 1e5).rounded()), lo = Int32((p.lon * 1e5).rounded())
        let cla = Self.floorDiv(la, Self.cell), clo = Self.floorDiv(lo, Self.cell)
        let r = Int64((maxMetres / 400).rounded(.up)) + 1
        var best: Int32 = -1, bestDist = Double.infinity, bestScore = Double.infinity
        for dy in -r...r {
            for dx in -r...r {
                guard let arr = grid[(cla + dy) * 100_000 + (clo + dx)] else { continue }
                for i in arr {
                    let d = Geo.haversine(p.lat, p.lon, Double(nodeLat[Int(i)]) / 1e5, Double(nodeLon[Int(i)]) / 1e5)
                    if d > maxMetres { continue }
                    var pf = Double.infinity
                    for k in Int(offsets[Int(i)])..<Int(offsets[Int(i) + 1]) {
                        let f = snapPreference[Int(wayCategory[Int(edgeWay[Int(adjacent[k])])])]
                        if f < pf { pf = f }
                    }
                    let score = d * pf
                    if score < bestScore { bestScore = score; bestDist = d; best = i }
                }
            }
        }
        return best >= 0 ? Snap(node: best, distance: bestDist, coordinate: coordinate(of: best)) : nil
    }

    /// Nearest way (by perpendicular distance to its segments) within `maxMetres`, restricted to the
    /// given category indices. Used to pick a way when the map is tapped.
    func nearestWay(to p: LatLon, maxMetres: Double, categories allowed: Set<Int8>) -> (way: Int, distance: Double)? {
        let la = Int32((p.lat * 1e5).rounded()), lo = Int32((p.lon * 1e5).rounded())
        let cla = Self.floorDiv(la, Self.cell), clo = Self.floorDiv(lo, Self.cell)
        let r: Int64 = max(2, Int64((maxMetres / 400).rounded(.up)) + 2)
        var best = -1, bestDist = Double.infinity
        var seen = Set<Int32>()
        for dy in -r...r {
            for dx in -r...r {
                guard let arr = grid[(cla + dy) * 100_000 + (clo + dx)] else { continue }
                for i in arr {
                    let a = coordinate(of: i)
                    for k in Int(offsets[Int(i)])..<Int(offsets[Int(i) + 1]) {
                        let e = adjacent[k]
                        if !seen.insert(e & ~1).inserted { continue }
                        let w = edgeWay[Int(e)]
                        if !allowed.contains(wayCategory[Int(w)]) { continue }
                        let d = Geo.segmentDistance(p, a, coordinate(of: edgeTo[Int(e)]))
                        if d < bestDist { bestDist = d; best = Int(w) }
                    }
                }
            }
        }
        return best >= 0 && bestDist <= maxMetres ? (best, bestDist) : nil
    }
}
