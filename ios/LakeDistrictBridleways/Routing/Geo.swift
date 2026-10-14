import Foundation

/// A latitude/longitude pair in degrees. Used instead of CLLocationCoordinate2D inside the
/// routing engine so the engine stays free of MapKit and trivially Sendable.
nonisolated struct LatLon: Hashable, Sendable, Codable {
    var lat: Double
    var lon: Double

    init(_ lat: Double, _ lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

nonisolated enum Geo {
    static let earthRadius = 6_371_000.0

    /// Great-circle distance in metres between two points given in degrees.
    @inline(__always)
    static func haversine(_ la1: Double, _ lo1: Double, _ la2: Double, _ lo2: Double) -> Double {
        let p = Double.pi / 180
        let dLa = (la2 - la1) * p
        let dLo = (lo2 - lo1) * p
        let s1 = sin(dLa / 2), s2 = sin(dLo / 2)
        let a = s1 * s1 + cos(la1 * p) * cos(la2 * p) * s2 * s2
        return 2 * earthRadius * asin(min(1, sqrt(a)))
    }

    static func distance(_ a: LatLon, _ b: LatLon) -> Double {
        haversine(a.lat, a.lon, b.lat, b.lon)
    }

    /// Length of a polyline in metres.
    static func length(of coords: [LatLon]) -> Double {
        var len = 0.0
        if coords.count > 1 {
            for i in 1..<coords.count { len += distance(coords[i - 1], coords[i]) }
        }
        return len
    }

    /// Resample a path so consecutive points are roughly `step` metres apart (for elevation lookups).
    static func resample(_ coords: [LatLon], step: Double) -> [LatLon] {
        guard let first = coords.first else { return [] }
        var out = [first]
        var acc = 0.0
        if coords.count > 1 {
            for i in 1..<coords.count {
                let a = coords[i - 1], b = coords[i]
                let d = distance(a, b)
                if d == 0 { continue }
                var pos = step - acc
                while pos < d {
                    let f = pos / d
                    out.append(LatLon(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f))
                    pos += step
                }
                acc = (acc + d).truncatingRemainder(dividingBy: step)
            }
        }
        out.append(coords[coords.count - 1])
        return out
    }

    /// Total climb in metres with 5 m hysteresis to ignore DEM noise.
    static func ascent(_ eles: [Double]) -> Int {
        guard var base = eles.first else { return 0 }
        var asc = 0.0
        for e in eles.dropFirst() {
            if e > base + 5 { asc += e - base; base = e } else if e < base - 5 { base = e }
        }
        return Int(asc.rounded())
    }

    /// Distance in metres from point P to the segment AB, computed in a local flat frame.
    static func segmentDistance(_ p: LatLon, _ a: LatLon, _ b: LatLon) -> Double {
        let kx = 111_320 * cos(p.lat * .pi / 180), ky = 110_540.0
        let ax = (a.lon - p.lon) * kx, ay = (a.lat - p.lat) * ky
        let bx = (b.lon - p.lon) * kx, by = (b.lat - p.lat) * ky
        let dx = bx - ax, dy = by - ay
        let l2 = dx * dx + dy * dy
        if l2 == 0 { return (ax * ax + ay * ay).squareRoot() }
        let t = max(0, min(1, -(ax * dx + ay * dy) / l2))
        let cx = ax + t * dx, cy = ay + t * dy
        return (cx * cx + cy * cy).squareRoot()
    }
}

/// Encoded polyline (Google precision-5) decoding into flat [lat, lon, lat, lon…] in 1e-5 degree units.
nonisolated enum Polyline {
    static func decode(_ s: String) -> [Int32] {
        var out: [Int32] = []
        out.reserveCapacity(s.utf8.count / 2)
        var lat: Int32 = 0, lon: Int32 = 0
        var it = s.utf8.makeIterator()
        while true {
            guard let dLat = readValue(&it) else { break }
            lat &+= dLat
            guard let dLon = readValue(&it) else { break }
            lon &+= dLon
            out.append(lat)
            out.append(lon)
        }
        return out
    }

    private static func readValue(_ it: inout String.UTF8View.Iterator) -> Int32? {
        var shift: Int32 = 0
        var result: Int32 = 0
        while true {
            guard let c = it.next() else { return nil }
            let b = Int32(c) - 63
            result |= (b & 0x1f) << shift
            shift += 5
            if b < 0x20 { break }
        }
        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }
}
