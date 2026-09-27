import SwiftUI

/// Hosts the UIKit run surface so landscape safe areas and multi-touch stay in UIKit.
struct RunGameView: UIViewControllerRepresentable {
    let canonicalId: String
    let romData: Data
    var nearbySession = false
    var gameTitle: String = ""
    var onPauseCommand: (String) -> Void = { _ in }
    var overlayReloadGeneration: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(onPauseCommand: onPauseCommand)
    }

    func makeUIViewController(context: Context) -> RunSurfaceViewController {
        let controller = RunSurfaceViewController()
        controller.canonicalId = canonicalId
        controller.romData = romData
        controller.nearbySession = nearbySession
        controller.gameTitle = gameTitle
        controller.onPauseCommand = { command in
            context.coordinator.onPauseCommand(command)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: RunSurfaceViewController, context: Context) {
        uiViewController.canonicalId = canonicalId
        uiViewController.nearbySession = nearbySession
        uiViewController.gameTitle = gameTitle
        context.coordinator.onPauseCommand = onPauseCommand
        uiViewController.onPauseCommand = { command in
            context.coordinator.onPauseCommand(command)
        }
        if context.coordinator.overlayReloadGeneration != overlayReloadGeneration {
            context.coordinator.overlayReloadGeneration = overlayReloadGeneration
            uiViewController.reloadProductSettings()
        }
    }

    final class Coordinator {
        var onPauseCommand: (String) -> Void
        var overlayReloadGeneration = 0
        init(onPauseCommand: @escaping (String) -> Void) {
            self.onPauseCommand = onPauseCommand
        }
    }
}

struct NearbyRunGameContainer: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RunGameView(canonicalId: FlyNesNearbyBridge.sharedInstance.canonicalId,
                    romData: Data(), nearbySession: true,
                    gameTitle: FlyNesNearbyBridge.sharedInstance.gameTitle,
                    onPauseCommand: { command in
            if command == "game_center" {
                _ = FlyNesNearbyBridge.sharedInstance.returnLobby()
                dismiss()
            }
        })
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Pause drawer Resume / Game Center / Settings. Game Center pops to the library root.
/// The ROM is already resolved by the Game Center before this screen is pushed, which
/// is what keeps a launch failure inside the library instead of a separate error page.
struct RunGameContainer: View {
    let canonicalId: String
    let romData: Data
    let game: CatalogGame
    @Environment(\.locale) private var locale
    @Binding var path: NavigationPath
    @State private var showSettings = false
    @State private var overlayReloadGeneration = 0

    var body: some View {
        RunGameView(canonicalId: canonicalId, romData: romData, gameTitle: localizedTitle,
                    onPauseCommand: { command in
            if command == "game_center" { path = NavigationPath() }
            else if command == "settings" { showSettings = true }
        }, overlayReloadGeneration: overlayReloadGeneration)
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showSettings, onDismiss: {
            overlayReloadGeneration += 1
        }) {
            SettingsView()
        }
    }

    private var localizedTitle: String {
        FlyNesCatalogPresentation.title(forFields: ["titleEn": game.titleEn,
            "titleZhHans": game.titleZhHans, "titleUnknown": game.titleUnknown],
            locale: locale.identifier)["primary"] ?? game.displayName
    }
}
