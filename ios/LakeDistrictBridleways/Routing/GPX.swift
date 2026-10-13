import Foundation

nonisolated enum GPX {
    /// GPX 1.1 track from a list of coordinates and optional elevations (matches the web app output).
    static func document(name: String, coords: [LatLon], elevations: [Double]?) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"Lake District Bridleway Map\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n<trk><name>\(esc(name))</name><trkseg>\n"
        for (i, c) in coords.enumerated() {
            s += "<trkpt lat=\"\(String(format: "%.6f", c.lat))\" lon=\"\(String(format: "%.6f", c.lon))\">"
            if let e = elevations, i < e.count { s += "<ele>\(Int(e[i].rounded()))</ele>" }
            s += "</trkpt>\n"
        }
        return s + "</trkseg></trk>\n</gpx>\n"
    }
}
