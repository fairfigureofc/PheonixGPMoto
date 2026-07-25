import SwiftUI

@main
struct PheonixGPMotoApp: App {
    @State private var model = BenchmarkModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
