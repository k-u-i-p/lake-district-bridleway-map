import Foundation

nonisolated struct GPXPoint: Sendable {
    let coordinate: LatLon
    let elevation: Double?
}

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

    /// Track and route points from a GPX file.
    static func parse(_ data: Data) -> [GPXPoint] {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.points
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var points: [GPXPoint] = []
        private var lat: Double?, lon: Double?, ele: Double?
        private var inEle = false
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "trkpt", "rtept":
                lat = attributes["lat"].flatMap(Double.init)
                lon = attributes["lon"].flatMap(Double.init)
                ele = nil
            case "ele":
                inEle = true; text = ""
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inEle { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "ele":
                inEle = false
                ele = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case "trkpt", "rtept":
                if let la = lat, let lo = lon { points.append(GPXPoint(coordinate: LatLon(la, lo), elevation: ele)) }
                lat = nil; lon = nil; ele = nil
            default: break
            }
        }
    }
}
