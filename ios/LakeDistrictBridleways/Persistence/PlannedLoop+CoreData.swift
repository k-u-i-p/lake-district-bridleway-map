import CoreData

@objc(PlannedLoop)
public class PlannedLoop: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var isDraft: Bool
    @NSManaged public var lengthMetres: Double
    @NSManaged public var ascentMetres: NSNumber?
    @NSManaged public var coordinateData: Data?
    @NSManaged public var elevationData: Data?
    @NSManaged public var breakdownJSON: String?
    @NSManaged public var footpathPenalty: Double
    @NSManaged public var roadPenalty: Double
    @NSManaged public var reridePenalty: Double
    @NSManaged public var waypoints: NSSet?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PlannedLoop> {
        NSFetchRequest<PlannedLoop>(entityName: "PlannedLoop")
    }

    /// Saved (non-draft) loops, newest first.
    @nonobjc public class func savedLoopsRequest() -> NSFetchRequest<PlannedLoop> {
        let r = fetchRequest()
        r.predicate = NSPredicate(format: "isDraft == NO")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \PlannedLoop.createdAt, ascending: false)]
        return r
    }

    var orderedWaypoints: [Waypoint] {
        ((waypoints as? Set<Waypoint>) ?? []).sorted { $0.order < $1.order }
    }

    var coordinates: [LatLon] { BinaryCodec.unpackCoords(coordinateData) }
    var elevations: [Double]? { BinaryCodec.unpackDoubles(elevationData) }
    var ascent: Int? { ascentMetres?.intValue }

    var breakdown: [String: Double] {
        guard let s = breakdownJSON, let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Double] else { return [:] }
        return o
    }

    var routingOptions: RoutingOptions {
        RoutingOptions(footpathPenalty: footpathPenalty, roadPenalty: roadPenalty, reridePenalty: reridePenalty)
    }

    /// Replaces the waypoint set with the given coordinates, in order.
    func setWaypoints(_ points: [LatLon], in context: NSManagedObjectContext) {
        for w in orderedWaypoints { context.delete(w) }
        for (i, p) in points.enumerated() {
            let w = Waypoint(context: context)
            w.id = UUID(); w.order = Int16(i); w.latitude = p.lat; w.longitude = p.lon
            w.loop = self
        }
    }

    func setResult(coords: [LatLon], length: Double, byCategory: [String: Double], elevations: [Double]?, ascent: Int?) {
        coordinateData = coords.isEmpty ? nil : BinaryCodec.pack(coords)
        lengthMetres = length
        breakdownJSON = (try? JSONSerialization.data(withJSONObject: byCategory)).flatMap { String(data: $0, encoding: .utf8) }
        elevationData = elevations.map(BinaryCodec.pack)
        ascentMetres = ascent.map { NSNumber(value: $0) }
    }
}

@objc(Waypoint)
public class Waypoint: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var order: Int16
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var loop: PlannedLoop?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Waypoint> {
        NSFetchRequest<Waypoint>(entityName: "Waypoint")
    }

    var coordinate: LatLon { LatLon(latitude, longitude) }
}
