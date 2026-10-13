import MapKit
import UIKit

// MARK: - Overlays

/// A route line. Each route is drawn twice: a dark casing underneath and the coloured line on top.
nonisolated final class RoutePolyline: MKPolyline {
    var color: UIColor = .yellow
    var width: CGFloat = 3.5
    var alpha: CGFloat = 1
}

/// All the ways of one display layer, drawn in a single pass.
nonisolated final class LayerMultiPolyline: MKMultiPolyline {
    var layer: DisplayLayer?
}

nonisolated final class FocusPolygon: MKPolygon {}

// MARK: - Annotations

nonisolated final class WaypointAnnotation: MKPointAnnotation {
    let id: UUID
    var index: Int {
        didSet { title = index == 0 ? "Start" : "Waypoint \(index)" }
    }

    init(id: UUID, index: Int, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.index = index
        super.init()
        self.coordinate = coordinate
        self.title = index == 0 ? "Start" : "Waypoint \(index)"
        self.subtitle = "Drag to move"
    }
}

nonisolated final class PeakAnnotation: MKPointAnnotation {
    let rank: Int
    let elevation: Int
    init(rank: Int, peak: Peak) {
        self.rank = rank
        self.elevation = peak.elevation
        super.init()
        coordinate = CLLocationCoordinate2D(latitude: peak.coordinate.lat, longitude: peak.coordinate.lon)
        title = peak.name
    }
}

nonisolated final class LabelAnnotation: MKPointAnnotation {
    let label: MapLabel
    init(label: MapLabel) {
        self.label = label
        super.init()
        coordinate = CLLocationCoordinate2D(latitude: label.coordinate.lat, longitude: label.coordinate.lon)
        title = label.text
    }
}

/// The start marker of the open route.
nonisolated final class StartDotAnnotation: MKPointAnnotation {
    let color: UIColor
    init(coordinate: CLLocationCoordinate2D, color: UIColor) {
        self.color = color
        super.init()
        self.coordinate = coordinate
    }
}

// MARK: - Annotation views

final class WaypointView: MKAnnotationView {
    static let reuseID = "waypoint"
    private let label = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        layer.cornerRadius = 12
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.6
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.frame = bounds
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        addSubview(label)
        isDraggable = true
        canShowCallout = true
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "trash"), for: .normal)
        button.tintColor = .systemRed
        button.sizeToFit()
        rightCalloutAccessoryView = button
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var annotation: (any MKAnnotation)? {
        didSet { configure() }
    }

    func configure() {
        guard let a = annotation as? WaypointAnnotation else { return }
        label.text = a.index == 0 ? "S" : "\(a.index)"
        backgroundColor = a.index == 0 ? UIColor(hex: 0x111111) : UIColor(hex: 0xe41b23)
    }
}

final class PeakView: MKAnnotationView {
    static let reuseID = "peak"
    private let triangle = CAShapeLayer()
    private let label = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        isEnabled = false
        isUserInteractionEnabled = false
        frame = CGRect(x: 0, y: 0, width: 14, height: 12)
        centerOffset = CGPoint(x: 0, y: 0)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 7, y: 0)); path.addLine(to: CGPoint(x: 14, y: 12)); path.addLine(to: CGPoint(x: 0, y: 12)); path.close()
        triangle.path = path.cgPath
        triangle.fillColor = UIColor.white.cgColor
        triangle.shadowColor = UIColor.black.cgColor
        triangle.shadowOpacity = 1
        triangle.shadowRadius = 2
        triangle.shadowOffset = .zero
        layer.addSublayer(triangle)
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium).withWidth(.condensed)
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 1
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
        addSubview(label)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var annotation: (any MKAnnotation)? {
        didSet { configure() }
    }

    var showsLabel = true {
        didSet { label.isHidden = !showsLabel }
    }

    private func configure() {
        guard let p = annotation as? PeakAnnotation else { return }
        let text = NSMutableAttributedString(string: "\(p.rank). \(p.title ?? "") ", attributes: [.foregroundColor: UIColor.white])
        text.append(NSAttributedString(string: "\(p.elevation) m", attributes: [.foregroundColor: UIColor(white: 0.87, alpha: 1), .font: UIFont.systemFont(ofSize: 12, weight: .regular).withWidth(.condensed)]))
        label.attributedText = text
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 17, y: -3)
    }
}

final class LabelView: MKAnnotationView {
    static let reuseID = "label"
    private let label = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        isEnabled = false
        isUserInteractionEnabled = false
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 1
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = .zero
        addSubview(label)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var annotation: (any MKAnnotation)? {
        didSet { configure() }
    }

    private func configure() {
        guard let a = annotation as? LabelAnnotation else { return }
        label.transform = .identity
        label.font = UIFont.systemFont(ofSize: a.label.small ? 13 : 16, weight: .bold).withWidth(.condensed)
        label.attributedText = NSAttributedString(string: a.label.text.uppercased(), attributes: [.kern: 1.0, .font: label.font!, .foregroundColor: UIColor.white])
        label.sizeToFit()
        frame = CGRect(origin: .zero, size: label.bounds.size)
        label.center = CGPoint(x: bounds.midX, y: bounds.midY)
        label.transform = CGAffineTransform(rotationAngle: a.label.rotation * .pi / 180)
    }
}

final class StartDotView: MKAnnotationView {
    static let reuseID = "start"

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        isEnabled = false
        isUserInteractionEnabled = false
        frame = CGRect(x: 0, y: 0, width: 14, height: 14)
        layer.cornerRadius = 7
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.cgColor
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var annotation: (any MKAnnotation)? {
        didSet { configure() }
    }

    private func configure() {
        backgroundColor = (annotation as? StartDotAnnotation)?.color ?? .yellow
    }
}

extension UIFont {
    nonisolated func withWidth(_ width: UIFont.Width) -> UIFont {
        let traits: [UIFontDescriptor.TraitKey: Any] = [.width: width.rawValue]
        let desc = fontDescriptor.addingAttributes([.traits: traits])
        return UIFont(descriptor: desc, size: pointSize)
    }
}
