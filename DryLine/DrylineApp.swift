import SwiftUI

@main
struct DrylineApp: App {
    // Shared with ContentView via AppStorage — changing it in either place
    // updates both, and the choice persists between launches.
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.dark.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .dark
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.gold)
        }
    }
}
