import GoogleMaps
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
              !apiKey.isEmpty,
              apiKey != "$(GOOGLE_MAPS_API_KEY)"
        else { return true }
        GMSServices.provideAPIKey(apiKey)
        return true
    }
}

@main
struct PheonixGPMotoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = BenchmarkModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
