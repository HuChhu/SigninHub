import SwiftUI

@main
struct SigninHubApp: App {
    @StateObject private var engine = BackendEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}
