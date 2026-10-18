import SwiftUI

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: appDelegate.model)
        } label: {
            Label("RightClickAssistant", systemImage: "cursorarrow.click.2")
        }
        .menuBarExtraStyle(.window)
    }
}
