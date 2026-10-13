import MapKit

/// Raster tile layer (OpenTopoMap, CyclOSM, OSM) with a proper User-Agent and an on-disk cache, as the
/// tile servers' usage policies ask for.
nonisolated final class CachedTileOverlay: MKTileOverlay {
    let baseMap: BaseMap
    private let session: URLSession

    init(baseMap: BaseMap, template: String) {
        self.baseMap = baseMap
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20, directory: nil)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = ["User-Agent": "LakeDistrictBridleways/1.0 (iOS; +https://github.com)"]
        session = URLSession(configuration: config)
        super.init(urlTemplate: template)
        canReplaceMapContent = true
        maximumZ = baseMap.maximumZoom
        minimumZ = 6
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping @Sendable (Data?, (any Error)?) -> Void) {
        let task = session.dataTask(with: url(forTilePath: path)) { data, response, error in
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result(nil, URLError(.resourceUnavailable))
            } else {
                result(data, error)
            }
        }
        task.resume()
    }
}
