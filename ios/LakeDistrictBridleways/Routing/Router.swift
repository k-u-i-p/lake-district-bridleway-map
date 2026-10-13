import Foundation

/// Cost multipliers per way category. Bridleways and byways always count ×1.
nonisolated struct RoutingOptions: Sendable, Equatable {
    var footpathPenalty: Double = 3
    var roadPenalty: Double = 5
    var reridePenalty: Double = 4

    var factors: [String: Double] {
        let fp = footpathPenalty, rd = roadPenalty
        return ["bridleway": 1, "boat": 1, "restricted": 1, "permissive": 1.1, "other": 1.2,
                "footpath": fp, "path": fp * 1.3, "cycleway": 1, "track": 2,
                "road_minor": rd, "road_major": rd * 1.6, "trunk": rd * 4, "ferry": 3]
    }
}

nonisolated struct Leg: Sendable {
    let coords: [LatLon]
    let length: Double
    let byCategory: [String: Double]
    let ways: Set<Int32>
    let cost: Double
}

/// A planned loop: every leg joined, returning to the first waypoint.
nonisolated final class LoopResult: Sendable, Identifiable {
    let id = UUID()
    let coords: [LatLon]
    let length: Double
    let byCategory: [String: Double]
    let legs: [Leg]

    init(coords: [LatLon], length: Double, byCategory: [String: Double], legs: [Leg]) {
        self.coords = coords
        self.length = length
        self.byCategory = byCategory
        self.legs = legs
    }
}

/// Binary min-heap of (key, node) pairs for A*.
nonisolated private struct MinHeap {
    var keys: [Double] = []
    var values: [Int32] = []

    var isEmpty: Bool { keys.isEmpty }

    mutating func push(_ k: Double, _ v: Int32) {
        keys.append(k); values.append(v)
        var i = keys.count - 1
        while i > 0 {
            let p = (i - 1) >> 1
            if keys[p] <= keys[i] { break }
            keys.swapAt(p, i); values.swapAt(p, i)
            i = p
        }
    }

    mutating func pop() -> (Double, Int32)? {
        guard let k = keys.first, let v = values.first else { return nil }
        let lk = keys.removeLast(), lv = values.removeLast()
        if !keys.isEmpty {
            keys[0] = lk; values[0] = lv
            var i = 0
            let n = keys.count
            while true {
                let l = 2 * i + 1, r = l + 1
                var s = i
                if l < n && keys[l] < keys[s] { s = l }
                if r < n && keys[r] < keys[s] { s = r }
                if s == i { break }
                keys.swapAt(s, i); values.swapAt(s, i)
                i = s
            }
        }
        return (k, v)
    }
}

nonisolated enum Router {
    /// A* from node `s` to node `t`. Ways in `used` cost `reridePenalty` times more.
    static func route(_ g: RouteGraph, from s: Int32, to t: Int32, options: RoutingOptions, used: Set<Int32> = []) -> Leg? {
        let fac = options.factors
        var catF = [Double](repeating: 1, count: g.categories.count)
        var minF = Double.infinity
        for (i, c) in g.categories.enumerated() {
            catF[i] = fac[c] ?? 1
            if catF[i] < minF { minF = catF[i] }
        }
        let up = options.reridePenalty
        let n = g.nodeCount
        var dist = [Double](repeating: .infinity, count: n)
        var prev = [Int32](repeating: -1, count: n)
        var done = [Bool](repeating: false, count: n)
        let target = g.coordinate(of: t)

        return g.nodeLat.withUnsafeBufferPointer { nlat in
            g.nodeLon.withUnsafeBufferPointer { nlon in
                g.offsets.withUnsafeBufferPointer { off in
                    g.adjacent.withUnsafeBufferPointer { adj in
                        g.edgeTo.withUnsafeBufferPointer { eTo in
                            g.edgeLength.withUnsafeBufferPointer { eLen in
                                g.edgeWay.withUnsafeBufferPointer { eWay in
                                    g.wayCategory.withUnsafeBufferPointer { wayCat in
                                        @inline(__always) func h(_ i: Int32) -> Double {
                                            Geo.haversine(Double(nlat[Int(i)]) / 1e5, Double(nlon[Int(i)]) / 1e5, target.lat, target.lon) * minF
                                        }
                                        var heap = MinHeap()
                                        dist[Int(s)] = 0
                                        heap.push(h(s), s)
                                        while let (_, u) = heap.pop() {
                                            let ui = Int(u)
                                            if done[ui] { continue }
                                            done[ui] = true
                                            if u == t { break }
                                            let du = dist[ui]
                                            for k in Int(off[ui])..<Int(off[ui + 1]) {
                                                let e = Int(adj[k])
                                                let v = eTo[e], w = eWay[e]
                                                var c = Double(eLen[e]) * catF[Int(wayCat[Int(w)])]
                                                if !used.isEmpty && used.contains(w) { c *= up }
                                                let nd = du + c
                                                if nd < dist[Int(v)] {
                                                    dist[Int(v)] = nd
                                                    prev[Int(v)] = Int32(e)
                                                    heap.push(nd + h(v), v)
                                                }
                                            }
                                        }
                                        if dist[Int(t)] == .infinity { return nil }
                                        var edges: [Int32] = []
                                        var v = t
                                        while v != s {
                                            let e = prev[Int(v)]
                                            edges.append(e)
                                            v = eTo[Int(e ^ 1)] // reverse edge's "to" is our "from"
                                        }
                                        edges.reverse()
                                        var coords = [g.coordinate(of: s)]
                                        coords.reserveCapacity(edges.count + 1)
                                        var byCat: [String: Double] = [:]
                                        var len = 0.0
                                        var ways = Set<Int32>()
                                        for e in edges {
                                            let ei = Int(e)
                                            coords.append(g.coordinate(of: eTo[ei]))
                                            let w = eWay[ei]
                                            let c = g.categories[Int(wayCat[Int(w)])]
                                            byCat[c, default: 0] += Double(eLen[ei])
                                            len += Double(eLen[ei])
                                            ways.insert(w)
                                        }
                                        return Leg(coords: coords, length: len, byCategory: byCat, ways: ways, cost: dist[Int(t)])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Loop through the waypoint nodes in order and back to the first. Ways ridden in earlier legs are
    /// penalised so the return uses different tracks where possible.
    static func loop(_ g: RouteGraph, nodes: [Int32], options: RoutingOptions) -> LoopResult? {
        guard !nodes.isEmpty else { return nil }
        let seq = nodes.count > 1 ? nodes + [nodes[0]] : nodes
        var used = Set<Int32>()
        var legs: [Leg] = []
        if seq.count > 1 {
            for i in 0..<(seq.count - 1) {
                guard let leg = route(g, from: seq[i], to: seq[i + 1], options: options, used: used) else { return nil }
                legs.append(leg)
                used.formUnion(leg.ways)
            }
        }
        var coords: [LatLon] = []
        var byCat: [String: Double] = [:]
        var len = 0.0
        for (i, l) in legs.enumerated() {
            coords.append(contentsOf: i == 0 ? l.coords : Array(l.coords.dropFirst()))
            len += l.length
            for (c, v) in l.byCategory { byCat[c, default: 0] += v }
        }
        return LoopResult(coords: coords, length: len, byCategory: byCat, legs: legs)
    }
}
