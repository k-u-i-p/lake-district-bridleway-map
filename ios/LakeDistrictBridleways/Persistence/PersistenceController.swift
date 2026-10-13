import CoreData

/// Owns the Core Data stack for one region. Saved loops and their waypoints live here, as does the
/// in-progress draft loop so planning survives relaunches. Every region has its own store file, so
/// its routes are only loaded while that region is open.
final class PersistenceController {
    private static var byRegion: [Region: PersistenceController] = [:]

    /// The store for a region, opened on first use and kept for the life of the app.
    static func forRegion(_ region: Region) -> PersistenceController {
        if let existing = byRegion[region] { return existing }
        let controller = PersistenceController(region: region)
        byRegion[region] = controller
        return controller
    }

    /// In-memory store for SwiftUI previews.
    static let preview: PersistenceController = {
        let controller = PersistenceController(region: .lakeDistrict, inMemory: true)
        let ctx = controller.container.viewContext
        let loop = PlannedLoop(context: ctx)
        loop.id = UUID(); loop.name = "Kentmere to Keswick"; loop.createdAt = .now; loop.updatedAt = .now
        loop.lengthMetres = 97_540; loop.ascentMetres = 2_310
        try? ctx.save()
        return controller
    }()

    let region: Region
    let container: NSPersistentContainer

    init(region: Region, inMemory: Bool = false) {
        self.region = region
        // All regions share the data model; only the store file differs.
        container = NSPersistentContainer(name: "LakeDistrictBridleways")
        let url = inMemory ? URL(fileURLWithPath: "/dev/null")
                           : NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(region.storeFileName)
        container.persistentStoreDescriptions.first?.url = url
        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data store failed to load: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    var context: NSManagedObjectContext { container.viewContext }

    /// Number of saved (non-draft) routes in this region's store.
    var savedRouteCount: Int {
        (try? context.count(for: PlannedLoop.savedLoopsRequest())) ?? 0
    }

    func save() {
        let ctx = container.viewContext
        guard ctx.hasChanges else { return }
        do { try ctx.save() } catch {
            ctx.rollback()
            assertionFailure("Core Data save failed: \(error)")
        }
    }
}

/// Packs coordinate and elevation arrays into Binary attributes.
nonisolated enum BinaryCodec {
    static func pack(_ coords: [LatLon]) -> Data {
        var flat: [Double] = []
        flat.reserveCapacity(coords.count * 2)
        for c in coords { flat.append(c.lat); flat.append(c.lon) }
        return flat.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func unpackCoords(_ data: Data?) -> [LatLon] {
        guard let data, data.count % 16 == 0 else { return [] }
        let n = data.count / 16
        return data.withUnsafeBytes { raw -> [LatLon] in
            let d = raw.bindMemory(to: Double.self)
            return (0..<n).map { LatLon(d[2 * $0], d[2 * $0 + 1]) }
        }
    }

    static func pack(_ values: [Double]) -> Data {
        values.map { Float($0) }.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func unpackDoubles(_ data: Data?) -> [Double]? {
        guard let data, !data.isEmpty, data.count % 4 == 0 else { return nil }
        return data.withUnsafeBytes { raw in raw.bindMemory(to: Float.self).map(Double.init) }
    }
}
