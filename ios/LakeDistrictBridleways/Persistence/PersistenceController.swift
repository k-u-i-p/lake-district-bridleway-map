import CoreData

/// Owns the Core Data stack. Saved loops, their waypoints and imported GPX tracks live here, as does
/// the in-progress draft loop so planning survives relaunches.
final class PersistenceController {
    static let shared = PersistenceController()

    /// In-memory store for SwiftUI previews.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let ctx = controller.container.viewContext
        let loop = PlannedLoop(context: ctx)
        loop.id = UUID(); loop.name = "Kentmere to Keswick"; loop.createdAt = .now; loop.updatedAt = .now
        loop.lengthMetres = 97_540; loop.ascentMetres = 2_310
        try? ctx.save()
        return controller
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "LakeDistrictBridleways")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data store failed to load: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    var context: NSManagedObjectContext { container.viewContext }

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
