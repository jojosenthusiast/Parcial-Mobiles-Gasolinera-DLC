import SwiftUI

@main
struct DLCOperationsApp: App {
    private let configuration = OperationsConfiguration.load()

    var body: some Scene {
        WindowGroup {
            OperationsRootView(configuration: configuration)
        }
    }
}
