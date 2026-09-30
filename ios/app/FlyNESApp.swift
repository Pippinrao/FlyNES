import SwiftUI

@main
struct FlyNESApp: App {
    @AppStorage("FlyNesLocaleTag") private var localeTag = "system"

    init() {
        // The shared snapshot is authoritative, including after a process restart.
        if let tag = FlyNesAppBridge.sharedInstance().settingsGet()["locale_tag"] as? String {
            UserDefaults.standard.set(tag, forKey: "FlyNesLocaleTag")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("-flynes.test.nearby_lobby") {
                    NavigationStack {
                        NearbyLobbyView()
                    }
                } else if ProcessInfo.processInfo.arguments.contains("-flynes.test.nearby_host_lobby_route") {
                    CatalogLibraryView(testStartInHostLobby: true)
                } else if ProcessInfo.processInfo.arguments.contains("-flynes.test.nearby_role_connected") {
                    CatalogLibraryView(testStartInNearbyEntry: true)
                } else {
                    #if FLYNES_FLUTTER
                    FlutterProductView().ignoresSafeArea()
                    #else
                    CatalogLibraryView()
                    #endif
                }
            }
                .environment(\.locale, localeTag == "system" ? .autoupdatingCurrent : Locale(identifier: localeTag))
        }
    }
}
