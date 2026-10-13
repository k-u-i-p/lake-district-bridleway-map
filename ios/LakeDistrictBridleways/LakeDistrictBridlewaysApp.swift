import SwiftUI

@main
struct LakeDistrictBridlewaysApp: App {
    /// The model for the open region; nil while the region picker is showing. Choosing a region
    /// builds a fresh model (network, graph and Core Data store) for it, and leaving the region
    /// releases them.
    @State private var model: AppModel?

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    ContentView(changeRegion: { self.model = nil })
                        .environment(model)
                        .environment(\.managedObjectContext, model.persistence.context)
                        .id(model.region)
                } else {
                    RegionPicker { model = AppModel(region: $0) }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
