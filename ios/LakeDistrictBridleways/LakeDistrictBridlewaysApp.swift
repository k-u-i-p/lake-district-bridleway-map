import SwiftUI

@main
struct LakeDistrictBridlewaysApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(\.managedObjectContext, model.persistence.context)
        }
    }
}
