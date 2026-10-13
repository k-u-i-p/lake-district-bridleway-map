import CoreData
import Foundation
import Observation
import os
import SwiftUI

/// Details shown when a way on the map is tapped.
struct WayInfo: Identifiable, Sendable {
    let id: Int
    let way: Way
    let category: String
    let coordinate: LatLon
}

/// A waypoint of the loop being planned, snapped to a graph node.
struct PlanWaypoint: Identifiable, Sendable, Hashable {
    let id: UUID
    var node: Int32
    var coordinate: LatLon
}

/// A request for the map to frame a region.
struct FitRequest: Identifiable, Sendable {
    let id = UUID()
    let south: Double, north: Double, west: Double, east: Double
    let animated: Bool
}

/// What the stats box is currently describing.
struct Stats: Sendable {
    let title: String
    let length: Double
    let ascent: Int?
    let profile: [Double]?
}

/// All application state: the loaded network and graph, map display options, routing settings, the
/// loop being planned, the reference loop and imported GPX tracks. Persists the draft loop and saved
/// loops through Core Data and the display preferences through UserDefaults.
@Observable
final class AppModel {
    // MARK: Network
    private(set) var network: NetworkData?
    private(set) var graph: RouteGraph?
    private(set) var reference: RouteSummary?
    private(set) var loadError: String?
    var status: String?

    // MARK: Display
    var baseMap: BaseMap { didSet { defaults.set(baseMap.rawValue, forKey: "baseMap") } }
    var visibleLayers: Set<String> { didSet { defaults.set(Array(visibleLayers), forKey: "visibleLayers") } }
    var showPeaks: Bool { didSet { defaults.set(showPeaks, forKey: "showPeaks") } }
    var showLabels: Bool { didSet { defaults.set(showLabels, forKey: "showLabels") } }
    var showFocus: Bool { didSet { defaults.set(showFocus, forKey: "showFocus") } }
    var showReference: Bool { didSet { defaults.set(showReference, forKey: "showReference") } }

    // MARK: Routing settings
    var routing = RoutingOptions() {
        didSet {
            defaults.set(routing.footpathPenalty, forKey: "footpathPenalty")
            defaults.set(routing.roadPenalty, forKey: "roadPenalty")
            defaults.set(routing.reridePenalty, forKey: "reridePenalty")
            if routing != oldValue { recompute() }
        }
    }

    // MARK: Planning
    var isPlanning = false
    private(set) var waypoints: [PlanWaypoint] = []
    private(set) var loop: LoopResult?
    private(set) var loopFailed = false
    private(set) var loopElevations: [Double]?
    private(set) var loopAscent: Int?
    private(set) var isFetchingElevation = false
    var elevationMessage: String?
    private(set) var isRouting = false
    private var routingGeneration = 0
    private var elevationTask: Task<Void, Never>?
    private(set) var loadedLoopID: UUID?

    // MARK: GPX overlay
    private(set) var gpxTrack: RouteSummary?

    // MARK: UI
    var selectedWay: WayInfo?
    var fitRequest: FitRequest?

    let persistence: PersistenceController
    private let defaults: UserDefaults
    private var statusTask: Task<Void, Never>?

    init(persistence: PersistenceController = .shared, defaults: UserDefaults = .standard) {
        self.persistence = persistence
        self.defaults = defaults
        baseMap = BaseMap(rawValue: defaults.string(forKey: "baseMap") ?? "") ?? .satellite
        if let saved = defaults.stringArray(forKey: "visibleLayers") {
            visibleLayers = Set(saved)
        } else {
            visibleLayers = Set(DisplayLayer.all.filter(\.defaultOn).map(\.key))
        }
        showPeaks = defaults.object(forKey: "showPeaks") as? Bool ?? true
        showLabels = defaults.object(forKey: "showLabels") as? Bool ?? true
        showFocus = defaults.object(forKey: "showFocus") as? Bool ?? true
        showReference = defaults.object(forKey: "showReference") as? Bool ?? true
        routing = RoutingOptions(footpathPenalty: defaults.object(forKey: "footpathPenalty") as? Double ?? 3,
                                 roadPenalty: defaults.object(forKey: "roadPenalty") as? Double ?? 5,
                                 reridePenalty: defaults.object(forKey: "reridePenalty") as? Double ?? 4)
    }

    // MARK: - Loading

    /// Parses the bundled network and builds the routing graph off the main thread, then restores the draft loop.
    func load() async {
        guard network == nil, loadError == nil else { return }
        status = "Loading network…"
        reference = RouteSummary.loadBundledReference()
        let result = await Task.detached(priority: .userInitiated) { () -> Result<(NetworkData, RouteGraph), Error> in
            do {
                let t0 = Date()
                let data = try NetworkData.loadBundled()
                let t1 = Date()
                let graph = RouteGraph.build(data)
                Logger(subsystem: "LakeDistrictBridleways", category: "network").info("Parsed \(data.ways.count) ways in \(Int(t1.timeIntervalSince(t0) * 1000)) ms; built graph with \(graph.nodeCount) nodes and \(graph.edgeCount) edges in \(Int(Date().timeIntervalSince(t1) * 1000)) ms")
                return .success((data, graph))
            } catch { return .failure(error) }
        }.value
        switch result {
        case .success(let (data, graph)):
            network = data
            self.graph = graph
            status = nil
            restoreDraft()
        case .failure(let error):
            loadError = "Could not load the network: \(error.localizedDescription)"
            status = nil
        }
    }

    func flashStatus(_ text: String, seconds: Double = 2) {
        statusTask?.cancel()
        status = text
        statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.status = nil
        }
    }

    // MARK: - Map helpers

    var peaks: [Peak] { network?.peaks ?? [] }

    func layerLength(_ layer: DisplayLayer) -> Double {
        guard let network else { return 0 }
        let idx = Set(layer.categories.compactMap { c in network.categories.firstIndex(of: c).map(Int8.init) })
        return network.ways.reduce(0.0) { idx.contains($1.category) ? $0 + Double($1.length) : $0 }
    }

    func fitFocusArea(animated: Bool = true) {
        fitRequest = FitRequest(south: FocusArea.south, north: FocusArea.north, west: FocusArea.west, east: FocusArea.east, animated: animated)
    }

    func fit(to coords: [LatLon], animated: Bool = true) {
        guard let f = coords.first else { return }
        var s = f.lat, n = f.lat, w = f.lon, e = f.lon
        for c in coords { s = min(s, c.lat); n = max(n, c.lat); w = min(w, c.lon); e = max(e, c.lon) }
        fitRequest = FitRequest(south: s, north: n, west: w, east: e, animated: animated)
    }

    /// Called when the map is tapped outside planning mode: picks the nearest visible way.
    func selectWay(near p: LatLon, toleranceMetres: Double) {
        guard let graph, let network else { return }
        var cats = Set<Int8>()
        for l in DisplayLayer.all where visibleLayers.contains(l.key) {
            for c in l.categories { if let i = network.categories.firstIndex(of: c) { cats.insert(Int8(i)) } }
        }
        guard !cats.isEmpty, let hit = graph.nearestWay(to: p, maxMetres: toleranceMetres, categories: cats) else {
            selectedWay = nil
            return
        }
        let way = network.ways[hit.way]
        selectedWay = WayInfo(id: hit.way, way: way, category: network.categories[Int(way.category)], coordinate: p)
    }

    // MARK: - Planning

    var canPlan: Bool { graph != nil }

    func togglePlanning() {
        isPlanning.toggle()
        if isPlanning { selectedWay = nil }
    }

    func addWaypoint(at p: LatLon) {
        guard let graph else { flashStatus("The route network is still loading"); return }
        guard let snap = graph.nearest(to: p, maxMetres: 400) else {
            flashStatus("No path or road within 400 m of that point")
            return
        }
        waypoints.append(PlanWaypoint(id: UUID(), node: snap.node, coordinate: snap.coordinate))
        waypointsChanged()
    }

    func moveWaypoint(_ id: UUID, to p: LatLon) {
        guard let graph, let i = waypoints.firstIndex(where: { $0.id == id }) else { return }
        if let snap = graph.nearest(to: p, maxMetres: 400) {
            waypoints[i].node = snap.node
            waypoints[i].coordinate = snap.coordinate
        } else {
            flashStatus("No path or road within 400 m of that point")
            waypoints[i] = waypoints[i] // trigger an update so the marker snaps back
        }
        waypointsChanged()
    }

    func removeWaypoint(_ id: UUID) {
        waypoints.removeAll { $0.id == id }
        waypointsChanged()
    }

    func undoWaypoint() {
        guard !waypoints.isEmpty else { return }
        waypoints.removeLast()
        waypointsChanged()
    }

    func clearPlan() {
        waypoints = []
        loadedLoopID = nil
        waypointsChanged()
    }

    private func waypointsChanged() {
        saveDraft()
        recompute()
    }

    /// Re-routes the loop through the current waypoints on a background task.
    func recompute() {
        elevationTask?.cancel()
        elevationTask = nil
        isFetchingElevation = false
        elevationMessage = nil
        loopElevations = nil
        loopAscent = nil
        loopFailed = false
        routingGeneration += 1
        let generation = routingGeneration
        guard let graph, waypoints.count >= 2 else {
            loop = nil
            isRouting = false
            return
        }
        let nodes = waypoints.map(\.node)
        let options = routing
        isRouting = true
        Task {
            let t0 = Date()
            let result = await Task.detached(priority: .userInitiated) { Router.loop(graph, nodes: nodes, options: options) }.value
            Logger(subsystem: "LakeDistrictBridleways", category: "routing").info("Routed \(nodes.count) waypoints in \(Int(Date().timeIntervalSince(t0) * 1000)) ms: \(result.map { Int($0.length) } ?? -1) m")
            guard generation == routingGeneration else { return }
            isRouting = false
            loop = result
            loopFailed = result == nil
        }
    }

    /// Elevation samples every 100 m along the planned loop, from Open-Meteo.
    func fetchElevation() {
        guard let loop, !isFetchingElevation else { return }
        let samples = Geo.resample(loop.coords, step: 100)
        let loopID = loop.id
        isFetchingElevation = true
        elevationMessage = "Fetching elevation…"
        elevationTask = Task {
            do {
                let eles = try await ElevationService.fetch(samples) { fraction in
                    Task { @MainActor in
                        guard self.isFetchingElevation, self.loop?.id == loopID else { return }
                        self.elevationMessage = "Fetching elevation from Open-Meteo… \(Int(fraction * 100))%"
                    }
                }
                guard loop.id == loopID, self.loop?.id == loopID else { return }
                loopElevations = eles
                loopAscent = Geo.ascent(eles)
                elevationMessage = "\(loopAscent ?? 0) m of climbing. The GPX now includes elevation."
                isFetchingElevation = false
                updateLoadedLoopResult()
            } catch {
                guard self.loop?.id == loopID else { return }
                isFetchingElevation = false
                if case ElevationService.ElevationError.cancelled = error { elevationMessage = nil; return }
                elevationMessage = "Elevation lookup failed: the free elevation service is rate-limited or offline. Try again later."
            }
        }
    }

    /// GPX text for the planned loop (resampled when elevation is attached, as the web app does).
    func plannedLoopGPX(name: String = "Planned loop") -> String? {
        guard let loop else { return nil }
        let pts = loopElevations != nil ? Geo.resample(loop.coords, step: 100) : loop.coords
        return GPX.document(name: name, coords: pts, elevations: loopElevations)
    }

    // MARK: - Stats

    var stats: Stats? {
        if let loop {
            return Stats(title: "Planned loop", length: loop.length, ascent: loopAscent, profile: loopElevations)
        }
        if let gpxTrack {
            return Stats(title: gpxTrack.name, length: gpxTrack.length, ascent: gpxTrack.ascent, profile: gpxTrack.profile)
        }
        if let reference, showReference {
            return Stats(title: reference.name, length: reference.length, ascent: reference.ascent, profile: reference.profile)
        }
        return nil
    }

    // MARK: - GPX import

    func importGPX(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { flashStatus("Could not read that file"); return }
        let pts = GPX.parse(data)
        guard pts.count >= 2 else { flashStatus("No track points found in that file"); return }
        let name = url.deletingPathExtension().lastPathComponent
        let coords = pts.map(\.coordinate)
        let eles = pts.compactMap(\.elevation).filter(\.isFinite)
        let ascent = eles.count > pts.count / 2 ? Geo.ascent(eles) : nil
        let summary = RouteSummary(name: name, coords: coords, length: Geo.length(of: coords), ascent: ascent, profile: ascent != nil ? eles : nil)

        let track = GPXTrack(context: persistence.context)
        track.id = summary.id; track.name = name; track.importedAt = .now
        track.lengthMetres = summary.length
        track.ascentMetres = ascent.map { NSNumber(value: $0) }
        track.pointData = BinaryCodec.pack(coords)
        track.elevationData = summary.profile.map(BinaryCodec.pack)
        persistence.save()

        show(track: summary)
    }

    func show(track: RouteSummary?) {
        gpxTrack = track
        if let track { fit(to: track.coords) }
    }

    func delete(track: GPXTrack) {
        if gpxTrack?.id == track.id { gpxTrack = nil }
        persistence.context.delete(track)
        persistence.save()
    }

    // MARK: - Core Data: draft and saved loops

    private func draftLoop(create: Bool) -> PlannedLoop? {
        let r = PlannedLoop.fetchRequest()
        r.predicate = NSPredicate(format: "isDraft == YES")
        r.fetchLimit = 1
        if let d = try? persistence.context.fetch(r).first { return d }
        guard create else { return nil }
        let d = PlannedLoop(context: persistence.context)
        d.id = UUID(); d.name = "Draft"; d.isDraft = true; d.createdAt = .now; d.updatedAt = .now
        return d
    }

    private func saveDraft() {
        guard let d = draftLoop(create: true) else { return }
        d.updatedAt = .now
        d.footpathPenalty = routing.footpathPenalty
        d.roadPenalty = routing.roadPenalty
        d.reridePenalty = routing.reridePenalty
        d.setWaypoints(waypoints.map(\.coordinate), in: persistence.context)
        persistence.save()
    }

    private func restoreDraft() {
        guard let graph, let d = draftLoop(create: false) else { return }
        let restored = d.orderedWaypoints.compactMap { w -> PlanWaypoint? in
            guard let s = graph.nearest(to: w.coordinate, maxMetres: 400) else { return nil }
            return PlanWaypoint(id: w.id, node: s.node, coordinate: s.coordinate)
        }
        waypoints = restored
        if !restored.isEmpty { recompute() }
    }

    /// Stores the current loop under `name`.
    func saveCurrentLoop(named name: String) {
        guard let loop else { return }
        let l = PlannedLoop(context: persistence.context)
        l.id = UUID()
        l.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Loop \(Format.km(loop.length))" : name
        l.isDraft = false
        l.createdAt = .now; l.updatedAt = .now
        l.footpathPenalty = routing.footpathPenalty
        l.roadPenalty = routing.roadPenalty
        l.reridePenalty = routing.reridePenalty
        l.setWaypoints(waypoints.map(\.coordinate), in: persistence.context)
        l.setResult(coords: loop.coords, length: loop.length, byCategory: loop.byCategory, elevations: loopElevations, ascent: loopAscent)
        persistence.save()
        loadedLoopID = l.id
        flashStatus("Saved “\(l.name)”")
    }

    /// Writes new elevation data back to the saved loop it was loaded from.
    private func updateLoadedLoopResult() {
        guard let loadedLoopID, let loop else { return }
        let r = PlannedLoop.fetchRequest()
        r.predicate = NSPredicate(format: "id == %@ AND isDraft == NO", loadedLoopID as CVarArg)
        guard let l = try? persistence.context.fetch(r).first, abs(l.lengthMetres - loop.length) < 1 else { return }
        l.setResult(coords: loop.coords, length: loop.length, byCategory: loop.byCategory, elevations: loopElevations, ascent: loopAscent)
        l.updatedAt = .now
        persistence.save()
    }

    /// Restores a saved loop's waypoints and settings, keeping its elevation data when the route still matches.
    func load(loop saved: PlannedLoop) {
        guard let graph else { return }
        routing = saved.routingOptions // may trigger recompute; waypoints are replaced below anyway
        waypoints = saved.orderedWaypoints.compactMap { w in
            graph.nearest(to: w.coordinate, maxMetres: 400).map { PlanWaypoint(id: UUID(), node: $0.node, coordinate: $0.coordinate) }
        }
        loadedLoopID = saved.id
        let storedLength = saved.lengthMetres
        let storedEles = saved.elevations
        let storedAscent = saved.ascent
        saveDraft()
        recompute()
        let generation = routingGeneration
        // Re-attach elevation once routing finishes, if the loop came out the same length.
        Task { [weak self] in
            while let self, self.isRouting, self.routingGeneration == generation {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let self, self.routingGeneration == generation, let loop = self.loop,
                  let eles = storedEles, abs(loop.length - storedLength) < 1 else { return }
            self.loopElevations = eles
            self.loopAscent = storedAscent ?? Geo.ascent(eles)
        }
        isPlanning = true
        fit(to: saved.coordinates.isEmpty ? waypoints.map(\.coordinate) : saved.coordinates)
    }

    func delete(loop: PlannedLoop) {
        if loadedLoopID == loop.id { loadedLoopID = nil }
        persistence.context.delete(loop)
        persistence.save()
    }
}
