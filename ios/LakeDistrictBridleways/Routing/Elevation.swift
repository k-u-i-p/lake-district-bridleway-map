import Foundation
import os

/// Elevation lookups from the Open-Meteo digital elevation model. The API is free and rate-limited,
/// so requests are chunked and spaced out, and retried with a long back-off after a 429.
nonisolated enum ElevationService {
    static let chunkSize = 100
    static let gap: UInt64 = 1_500_000_000 // ns between chunks

    enum ElevationError: Error { case failed, cancelled }
    private static let log = Logger(subsystem: "LakeDistrictBridleways", category: "elevation")

    static func fetch(_ points: [LatLon], progress: @Sendable @escaping (Double) -> Void) async throws -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(points.count)
        var i = 0
        while i < points.count {
            try Task.checkCancellation()
            let chunk = Array(points[i..<min(i + chunkSize, points.count)])
            var got: [Double]? = nil
            for attempt in 0..<4 {
                let lat = chunk.map { String(format: "%.5f", $0.lat) }.joined(separator: ",")
                let lon = chunk.map { String(format: "%.5f", $0.lon) }.joined(separator: ",")
                guard let url = URL(string: "https://api.open-meteo.com/v1/elevation?latitude=\(lat)&longitude=\(lon)") else { throw ElevationError.failed }
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 200,
                       let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let eles = root["elevation"] as? [Double], eles.count == chunk.count {
                        got = eles
                        break
                    }
                    log.error("Elevation chunk at \(i) failed: HTTP \(status) \(String(data: data.prefix(200), encoding: .utf8) ?? "")")
                    if status != 429 { break }
                    // Open-Meteo's limit is per minute, so back off 20, 40, then 60 seconds.
                    try await Task.sleep(nanoseconds: 20_000_000_000 * UInt64(attempt + 1))
                } catch is CancellationError {
                    throw ElevationError.cancelled
                } catch {
                    log.error("Elevation chunk at \(i) failed: \(error)")
                    break
                }
            }
            guard let eles = got else { throw ElevationError.failed }
            out.append(contentsOf: eles)
            i += chunkSize
            progress(min(1, Double(i) / Double(points.count)))
            if i < points.count { try await Task.sleep(nanoseconds: gap) }
        }
        return out
    }
}
