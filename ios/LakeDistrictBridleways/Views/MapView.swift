import MapKit
import SwiftUI

/// MKMapView subclass that reports size changes, so the focus area can be framed once the view has
/// its real size (and re-framed on rotation until the user moves the map).
final class FocusMapView: MKMapView {
    var onSizeChange: ((CGSize) -> Void)?
    private var lastSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize, bounds.width > 0, bounds.height > 0 {
            lastSize = bounds.size
            onSizeChange?(bounds.size)
        }
    }
}

/// The map. Bridges `AppModel` to an `MKMapView`: base map and tile overlays, the rights-of-way layers,
/// the open route, waypoint markers, peaks, labels and the focus outline.
struct MapView: UIViewRepresentable {
    let model: AppModel
    /// Screen area covered by the planner panel, used when framing routes.
    var panelInsets: UIEdgeInsets

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> FocusMapView {
        let map = FocusMapView()
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.showsCompass = false // the floating controls sit where the compass would appear
        map.showsScale = true
        map.register(WaypointView.self, forAnnotationViewWithReuseIdentifier: WaypointView.reuseID)
        map.register(PeakView.self, forAnnotationViewWithReuseIdentifier: PeakView.reuseID)
        map.register(LabelView.self, forAnnotationViewWithReuseIdentifier: LabelView.reuseID)
        map.register(StartDotView.self, forAnnotationViewWithReuseIdentifier: StartDotView.reuseID)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.ignore(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        map.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.require(toFail: doubleTap)
        map.addGestureRecognizer(tap)

        let coordinator = context.coordinator
        map.onSizeChange = { [weak map, weak coordinator] _ in
            guard let map, let coordinator, !coordinator.userHasMovedMap else { return }
            let f = coordinator.model.region.focus
            coordinator.fit(FitRequest(south: f.south, north: f.north, west: f.west, east: f.east, animated: false), on: map)
        }
        return map
    }

    func updateUIView(_ map: FocusMapView, context: Context) {
        context.coordinator.apply(to: map, insets: panelInsets)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let model: AppModel
        private var insets = UIEdgeInsets.zero

        private var tileOverlay: CachedTileOverlay?
        private var appliedBase: BaseMap?
        private var layerOverlays: [String: LayerMultiPolyline] = [:]
        private var layersBuilding: Set<String> = []
        private var graphApplied = false
        private var focusOverlay: FocusPolygon?
        private var loopItems: [AnyObject] = [], loopID: UUID?
        private var waypointAnnotations: [UUID: WaypointAnnotation] = [:]
        private var peakAnnotations: [PeakAnnotation] = []
        private var peaksShown = false
        private var labelAnnotations: [LabelAnnotation] = []
        private var labelsShown = false
        private var fitID: UUID?
        private var showPeakLabels = true
        private var showPlaceLabels = true
        /// Once the user (or a route fit) has moved the map, size changes no longer re-frame the focus area.
        var userHasMovedMap = false

        init(model: AppModel) { self.model = model }

        // MARK: Applying model state

        func apply(to map: MKMapView, insets: UIEdgeInsets) {
            // Kept only for framing. Do not copy these into map.layoutMargins: MapKit adds layout
            // margins on top of the edge padding passed to setVisibleMapRect, which over-zooms the fit.
            self.insets = insets
            applyBaseMap(model.baseMap, to: map)
            applyFocus(model.showFocus, to: map)
            applyLayers(to: map)
            applyLoop(to: map)
            applyWaypoints(to: map)
            applyPeaks(to: map)
            applyLabels(to: map)
            if let req = model.fitRequest, req.id != fitID {
                fitID = req.id
                userHasMovedMap = true
                fit(req, on: map)
            }
        }

        private func applyBaseMap(_ base: BaseMap, to map: MKMapView) {
            guard base != appliedBase else { return }
            appliedBase = base
            if let old = tileOverlay { map.removeOverlay(old); tileOverlay = nil }
            if let template = base.tileTemplate {
                let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
                config.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = config
                let overlay = CachedTileOverlay(baseMap: base, template: template)
                tileOverlay = overlay
                map.insertOverlay(overlay, at: 0, level: .aboveLabels)
            } else if base == .satellite {
                let config = MKImageryMapConfiguration(elevationStyle: .flat)
                map.preferredConfiguration = config
            } else {
                let config = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
                config.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = config
            }
        }

        private func applyFocus(_ show: Bool, to map: MKMapView) {
            if show, focusOverlay == nil {
                let f = model.region.focus
                let c = [CLLocationCoordinate2D(latitude: f.south, longitude: f.west),
                         CLLocationCoordinate2D(latitude: f.north, longitude: f.west),
                         CLLocationCoordinate2D(latitude: f.north, longitude: f.east),
                         CLLocationCoordinate2D(latitude: f.south, longitude: f.east)]
                let poly = FocusPolygon(coordinates: c, count: c.count)
                focusOverlay = poly
                map.addOverlay(poly, level: .aboveLabels)
            } else if !show, let f = focusOverlay {
                map.removeOverlay(f)
                focusOverlay = nil
            }
        }

        private func applyLayers(to map: MKMapView) {
            guard let graph = model.graph else { return }
            for layer in DisplayLayer.all {
                let wanted = model.visibleLayers.contains(layer.key)
                let existing = layerOverlays[layer.key]
                if wanted {
                    if let existing {
                        if !map.overlays.contains(where: { $0 === existing }) { map.addOverlay(existing, level: .aboveLabels) }
                    } else if !layersBuilding.contains(layer.key) {
                        layersBuilding.insert(layer.key)
                        model.status = "Drawing \(layer.name.lowercased())…"
                        let cats = Set(layer.categories.compactMap(graph.categoryIndex))
                        Task { [weak self, weak map] in
                            let lines = await Task.detached(priority: .userInitiated) { () -> [[LatLon]] in
                                var out: [[LatLon]] = []
                                for w in 0..<graph.ways.count where cats.contains(graph.wayCategory[w]) {
                                    out.append(graph.coordinates(ofWay: w))
                                }
                                return out
                            }.value
                            guard let self, let map else { return }
                            let polylines = lines.map { line -> MKPolyline in
                                let c = line.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                                return MKPolyline(coordinates: c, count: c.count)
                            }
                            let multi = LayerMultiPolyline(polylines)
                            multi.layer = layer
                            self.layerOverlays[layer.key] = multi
                            self.layersBuilding.remove(layer.key)
                            if self.model.status?.hasPrefix("Drawing") == true { self.model.status = nil }
                            if self.model.visibleLayers.contains(layer.key) {
                                map.addOverlay(multi, level: .aboveLabels)
                                self.bringRoutesToFront(on: map)
                            }
                        }
                    }
                } else if let existing, map.overlays.contains(where: { $0 === existing }) {
                    map.removeOverlay(existing)
                }
            }
        }

        /// Routes must draw above the rights-of-way layers, which can be added later than the routes.
        private func bringRoutesToFront(on map: MKMapView) {
            for item in loopItems {
                if let o = item as? MKOverlay, map.overlays.contains(where: { $0 === o }) {
                    map.removeOverlay(o)
                    map.addOverlay(o, level: .aboveLabels)
                }
            }
        }

        private func routeItems(_ coords: [LatLon], color: UIColor) -> [AnyObject] {
            let c = coords.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            let casing = RoutePolyline(coordinates: c, count: c.count)
            casing.color = .black; casing.width = 7; casing.alpha = 0.5
            let line = RoutePolyline(coordinates: c, count: c.count)
            line.color = color; line.width = 3.5
            var items: [AnyObject] = [casing, line]
            if let first = c.first { items.append(StartDotAnnotation(coordinate: first, color: color)) }
            return items
        }

        private func add(_ items: [AnyObject], to map: MKMapView) {
            for i in items {
                if let o = i as? MKOverlay { map.addOverlay(o, level: .aboveLabels) } else if let a = i as? MKAnnotation { map.addAnnotation(a) }
            }
        }

        private func remove(_ items: [AnyObject], from map: MKMapView) {
            for i in items {
                if let o = i as? MKOverlay { map.removeOverlay(o) } else if let a = i as? MKAnnotation { map.removeAnnotation(a) }
            }
        }

        private func applyLoop(to map: MKMapView) {
            let id = model.loop?.id
            guard id != loopID else { return }
            remove(loopItems, from: map)
            loopItems = []
            loopID = id
            if let loop = model.loop {
                loopItems = routeItems(loop.coords, color: UIColor(hex: 0xffd400))
                add(loopItems, to: map)
            }
        }

        /// Waypoint markers are only shown while editing; a route being viewed is just its line.
        private func applyWaypoints(to map: MKMapView) {
            let wps = model.isEditing ? model.waypoints : []
            let ids = Set(wps.map(\.id))
            for (id, a) in waypointAnnotations where !ids.contains(id) {
                map.removeAnnotation(a)
                waypointAnnotations[id] = nil
            }
            for (i, wp) in wps.enumerated() {
                let coord = CLLocationCoordinate2D(latitude: wp.coordinate.lat, longitude: wp.coordinate.lon)
                if let a = waypointAnnotations[wp.id] {
                    if a.index != i { a.index = i; (map.view(for: a) as? WaypointView)?.configure() }
                    if a.coordinate.latitude != coord.latitude || a.coordinate.longitude != coord.longitude { a.coordinate = coord }
                } else {
                    let a = WaypointAnnotation(id: wp.id, index: i, coordinate: coord)
                    waypointAnnotations[wp.id] = a
                    map.addAnnotation(a)
                }
            }
        }

        private func applyPeaks(to map: MKMapView) {
            if peakAnnotations.isEmpty, !model.peaks.isEmpty {
                peakAnnotations = model.peaks.enumerated().map { PeakAnnotation(rank: $0.offset + 1, peak: $0.element) }
            }
            if model.showPeaks, !peaksShown, !peakAnnotations.isEmpty {
                map.addAnnotations(peakAnnotations); peaksShown = true
            } else if !model.showPeaks, peaksShown {
                map.removeAnnotations(peakAnnotations); peaksShown = false
            }
        }

        private func applyLabels(to map: MKMapView) {
            if labelAnnotations.isEmpty { labelAnnotations = model.region.labels.map(LabelAnnotation.init) }
            if model.showLabels, !labelsShown {
                map.addAnnotations(labelAnnotations); labelsShown = true
            } else if !model.showLabels, labelsShown {
                map.removeAnnotations(labelAnnotations); labelsShown = false
            }
        }

        func fit(_ req: FitRequest, on map: MKMapView) {
            let sw = MKMapPoint(CLLocationCoordinate2D(latitude: req.south, longitude: req.west))
            let ne = MKMapPoint(CLLocationCoordinate2D(latitude: req.north, longitude: req.east))
            let rect = MKMapRect(x: min(sw.x, ne.x), y: min(sw.y, ne.y), width: abs(ne.x - sw.x), height: abs(ne.y - sw.y))
            let pad = UIEdgeInsets(top: insets.top + 24, left: insets.left + 16, bottom: insets.bottom + 16, right: insets.right + 16)
            map.setVisibleMapRect(rect, edgePadding: pad, animated: req.animated)
        }

        // MARK: Gestures

        @objc func ignore(_ g: UITapGestureRecognizer) {}

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let map = g.view as? MKMapView else { return }
            let point = g.location(in: map)
            let coord = map.convert(point, toCoordinateFrom: map)
            let p = LatLon(coord.latitude, coord.longitude)
            if model.isPlanning {
                model.addWaypoint(at: p)
            } else {
                let mapPointsPerPoint = map.visibleMapRect.size.width / Double(map.bounds.width)
                let metresPerPoint = mapPointsPerPoint / MKMapPointsPerMeterAtLatitude(coord.latitude)
                model.selectWay(near: p, toleranceMetres: max(8, metresPerPoint * 14))
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Let taps on waypoint markers and their callouts through to MapKit only.
            var v = touch.view
            while let cur = v {
                if let av = cur as? MKAnnotationView, av.isEnabled { return false }
                if String(describing: type(of: cur)).contains("Callout") { return false }
                v = cur.superview
            }
            return true
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let multi = overlay as? LayerMultiPolyline, let layer = multi.layer {
                let r = MKMultiPolylineRenderer(multiPolyline: multi)
                r.strokeColor = UIColor(hex: layer.colorHex).withAlphaComponent(0.9)
                r.lineWidth = layer.thin ? 2 : 3
                r.lineCap = .round
                r.lineJoin = .round
                if layer.dashed { r.lineDashPattern = layer.thin ? [3, 5] : [6, 6] }
                return r
            }
            if let route = overlay as? RoutePolyline {
                let r = MKPolylineRenderer(polyline: route)
                r.strokeColor = route.color
                r.lineWidth = route.width
                r.alpha = route.alpha
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            if let focus = overlay as? FocusPolygon {
                let r = MKPolygonRenderer(polygon: focus)
                r.strokeColor = UIColor.white.withAlphaComponent(0.7)
                r.fillColor = .clear
                r.lineWidth = 1.5
                r.lineDashPattern = [6, 8]
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is WaypointAnnotation:
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: WaypointView.reuseID, for: annotation)
                v.displayPriority = .required
                return v
            case is PeakAnnotation:
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: PeakView.reuseID, for: annotation) as? PeakView
                v?.showsLabel = showPeakLabels
                v?.displayPriority = .required
                return v
            case is LabelAnnotation:
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: LabelView.reuseID, for: annotation)
                v.isHidden = !showPlaceLabels
                v.displayPriority = .required
                return v
            case is StartDotAnnotation:
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: StartDotView.reuseID, for: annotation)
                v.displayPriority = .required
                return v
            default:
                return nil
            }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard let a = view.annotation as? WaypointAnnotation else { return }
            switch newState {
            case .ending:
                view.dragState = .none
                model.moveWaypoint(a.id, to: LatLon(a.coordinate.latitude, a.coordinate.longitude))
            case .canceling:
                view.dragState = .none
            default:
                break
            }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let a = view.annotation as? WaypointAnnotation else { return }
            mapView.deselectAnnotation(a, animated: false)
            model.removeWaypoint(a.id)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // MapKit's own pan/pinch recognizers live on its first subview.
            if let recognizers = mapView.subviews.first?.gestureRecognizers,
               recognizers.contains(where: { $0.state == .began || $0.state == .changed || $0.state == .ended }) {
                userHasMovedMap = true
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let zoom = log2(360 * Double(mapView.bounds.width) / (mapView.region.span.longitudeDelta * 256))
            let peakLabels = zoom >= 11
            let placeLabels = zoom >= 9 && zoom <= 13
            if peakLabels != showPeakLabels {
                showPeakLabels = peakLabels
                for a in peakAnnotations { (mapView.view(for: a) as? PeakView)?.showsLabel = peakLabels }
            }
            if placeLabels != showPlaceLabels {
                showPlaceLabels = placeLabels
                for a in labelAnnotations { mapView.view(for: a)?.isHidden = !placeLabels }
            }
        }
    }
}
