import SwiftUI
import os.log
import UIKit

/// The shared session owns role, readiness and game identity across page transitions.
struct NearbyLobbyView: View {
    let testHostLobby: Bool
    init(testHostLobby: Bool = false) {
        self.testHostLobby = testHostLobby
        _state = State(initialValue: testHostLobby ? 3 : 0)
        _role = State(initialValue: testHostLobby ? 1 : 0)
    }
    @State private var state = 0
    @State private var role = 0
    @State private var localReady = false
    @State private var peerReady = false
    @State private var gameTitle = ""
    @State private var gameError = false
    @State private var pendingPicker = false
    @State private var loadingConfigToken = ""
    @State private var attemptedConfigToken = ""
    @State private var lastGuestConfigured = false
    @State private var ended = false
    private let background = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255)
    private let surface = Color(red: 27 / 255, green: 29 / 255, blue: 34 / 255)
    private let ink = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
    private let muted = Color(red: 190 / 255, green: 184 / 255, blue: 174 / 255)
    private let accent = Color(red: 255 / 255, green: 107 / 255, blue: 94 / 255)

    @ObservedObject private var covers = GameCoverModel.shared
    @State private var gamePaused = false
    @State private var gameKey = ""
    @State private var playbackGeneration: UInt64 = 0
    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 16) {
                VStack(spacing: 12) {
                    field("P1", value: playerName(first: true),
                          identifier: "nearby_lobby_row_network_owner")
                    field("P2", value: playerName(first: false),
                          identifier: "nearby_lobby_row_seat")
                }
                .frame(width: max(120, (geometry.size.width - 48) * 0.25), height: geometry.size.height - 32)
                .background(surface, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack {
                            Color(red: 18 / 255, green: 20 / 255, blue: 26 / 255)
                            if let cover = covers.image(for: gameKey) {
                                Image(uiImage: cover).resizable().interpolation(.none).scaledToFit()
                                    .accessibilityIdentifier("nearby_lobby_cover")
                            } else {
                                Text(gameTitle.isEmpty ? FlyNesLocalizedString("nearby.waitHostGame") : gameTitle)
                                    .nearbyRole(NearbyTypography.muted).foregroundStyle(muted)
                                    .multilineTextAlignment(.center).padding(8)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                        Text(gameTitle.isEmpty ? FlyNesLocalizedString("nearby.waitHostGame") : gameTitle)
                            .nearbyRole(NearbyTypography.body).foregroundStyle(ink).lineLimit(2)
                            .accessibilityIdentifier("nearby_lobby_row_rom_identity")
                    }
                    .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 12) {
                        Text(gameError ? "nearby.localGameMissing" :
                             (state == 6 && gamePaused ? "nearby.gamePaused" :
                              (state == 3 || state == 7 ? "nearby.screen.connected" : "nearby.status.matchingGame")))
                            .nearbyRole(NearbyTypography.muted).foregroundStyle(muted)
                            .accessibilityIdentifier("nearby_lobby_confirm_reason")
                        if state == 6 {
                            Button("nearby.resumeGame") { _ = FlyNesNearbyBridge.sharedInstance.resumeGame(); refresh() }
                                .nearbyRole(NearbyTypography.primaryAction).nearbyMinTap()
                                .frame(maxWidth: .infinity).buttonStyle(.borderedProminent).tint(accent)
                                .accessibilityIdentifier("nearby_lobby_resume")
                        }
                        if role == 1 {
                            Button(gameTitle.isEmpty ? "nearby.chooseGame" : "nearby.changeGame") {
                                NotificationCenter.default.post(name: Notification.Name("flynes.nearby.pickerRequest"), object: nil)
                            }
                            .disabled(state != 3 && state != 5 && state != 6)
                            .nearbyRole(NearbyTypography.action).nearbyMinTap()
                            .frame(maxWidth: .infinity).buttonStyle(.bordered).tint(accent)
                            .accessibilityIdentifier("nearby_lobby_choose_game")
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("nearby.lobby.title")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    NotificationCenter.default.post(name: Notification.Name("flynes.nearby.leaveRoom"), object: nil)
                } label: {
                    Image(systemName: "chevron.left").frame(minWidth: 48, minHeight: 48)
                }
                .accessibilityLabel(Text("nearby.action.backToGameCenter"))
                .accessibilityIdentifier("nearby_lobby_leave")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if state == 3 || state == 5 || state == 6 || state == 7 {
                    Button("nearby.action.disconnect") {
                        FlyNesNearbyBridge.sharedInstance.cancel()
                        endRoom()
                    }
                    .frame(minHeight: 48)
                    .accessibilityIdentifier("nearby_lobby_disconnect")
                }
            }
        }
        .onAppear { if !testHostLobby { refresh() } }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            if !testHostLobby { refresh() }
        }
    }

    private func refresh() {
        let bridge = FlyNesNearbyBridge.sharedInstance
        let snapshot = bridge.snapshot()
        let previousState = state
        state = (snapshot["state"] as? NSNumber)?.intValue ?? 0
        if previousState != state { os_log("FlyNesNearbyUI event=lobby state=%d", log: .default, type: .info, state) }
        playbackGeneration = bridge.playbackGeneration
        let wasPaused = gamePaused
        gamePaused = (snapshot["paused"] as? NSNumber)?.boolValue ?? false
        if wasPaused && !gamePaused && state == 6 {
            NotificationCenter.default.post(name: Notification.Name("flynes.nearby.resumed"), object: nil)
        }
        if state == 4 { endRoom(); return }
        role = (snapshot["role"] as? NSNumber)?.intValue ?? 0
        localReady = ((snapshot["localReady"] as? NSNumber)?.intValue ?? 0) != 0
        peerReady = ((snapshot["peerReady"] as? NSNumber)?.intValue ?? 0) != 0
        if state == 3 || state == 7 {
            gameTitle = ""
            gameError = false
            loadingConfigToken = ""
            attemptedConfigToken = ""
            lastGuestConfigured = false
        }
        if pendingPicker && state == 3 {
            pendingPicker = false
            NotificationCenter.default.post(name: Notification.Name("flynes.nearby.pickerRequest"), object: nil)
        }
        if role == 1 && state == 5 { gameTitle = bridge.gameTitle }
        if state == 5 && role == 2 {
            let peerKey = (snapshot["peerGameKey"] as? String) ?? ""
            let configToken = (snapshot["peerConfigToken"] as? String) ?? ""
            let reason = (snapshot["reason"] as? NSNumber)?.intValue ?? 0
            let configured = ((snapshot["localConfigured"] as? NSNumber)?.intValue ?? 0) != 0 &&
                reason != 7 && reason != 8
            if lastGuestConfigured && !configured {
                attemptedConfigToken = ""
                loadingConfigToken = ""
            }
            lastGuestConfigured = configured
            if configured && attemptedConfigToken.isEmpty { attemptedConfigToken = configToken }
            if !peerKey.isEmpty && !configToken.isEmpty && attemptedConfigToken != configToken {
                attemptedConfigToken = configToken
                loadingConfigToken = configToken
                gameError = false
                let row = FlyNesAppBridge.sharedInstance().catalogGame(forNearbyKey: peerKey)
                os_log("FlyNesNearbyUI event=guestMatch matched=%d", log: .default, type: .info, row == nil ? 0 : 1)
                guard let row, let localKey = row["canonicalId"] as? String else { gameError = true; return }
                let title = CatalogGameFactory.game(from: row, localeIdentifier: locale.identifier)?.titlePrimary ?? peerKey
                CatalogSourceModel.shared.prepareROM(localKey) { result in
                    guard loadingConfigToken == configToken,
                          (bridge.snapshot()["peerConfigToken"] as? String) == configToken else { return }
                    switch result {
                    case .success(let rom):
                        if bridge.selectGuestGameROM(rom, canonicalID: localKey, title: title) {
                            gameTitle = title
                            gameError = false
                        } else {
                            os_log("FlyNesNearbyUI event=guestConfigure failed reason=%d", log: .default, type: .info, (bridge.snapshot()["reason"] as? NSNumber)?.intValue ?? -1)
                            gameError = true
                        }
                    case .failure(let error):
                        os_log("FlyNesNearbyUI event=guestRomRead failed code=%d", log: .default, type: .info, (error as NSError).code)
                        gameError = true
                    }
                    loadingConfigToken = ""
                }
            }
        }
        if state == 5 || state == 6 {
            gameTitle = bridge.gameTitle
            if gameKey != bridge.canonicalId {
                gameKey = bridge.canonicalId
                covers.preload(canonicalIds: gameKey.isEmpty ? [] : [gameKey])
            }
        } else { gameKey = "" }
        if state == 6 && !gamePaused {
            NotificationCenter.default.post(name: Notification.Name("flynes.nearby.playRequest"),
                                            object: NSNumber(value: playbackGeneration))
        }
    }

    private func endRoom() {
        guard !ended else { return }
        ended = true
        NotificationCenter.default.post(name: Notification.Name("flynes.nearby.disconnected"), object: nil)
    }

    private func playerName(first: Bool) -> String {
        guard state == 3 || state == 5 || state == 6 || state == 7 else { return "—" }
        return FlyNesLocalizedString(first == (role == 1) ? "nearby.playerLocal" : "nearby.playerPeer")
    }

    private func field(_ title: LocalizedStringKey, value: String,
                       identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .nearbyRole(NearbyTypography.sectionTitle)
                .foregroundStyle(ink)
            Text(value)
                .nearbyRole(NearbyTypography.muted)
                .foregroundStyle(muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier(identifier)
    }
}

/// Embeds the existing game center in its own UIKit host so the room route
/// cannot recursively build the game center's nearby navigation tree.
struct NearbyCatalogPicker: UIViewControllerRepresentable {
    let onSelect: (CatalogGame, Data, @escaping (Bool) -> Void) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIHostingController<CatalogLibraryView> {
        UIHostingController(rootView: CatalogLibraryView(
            nearbySelection: onSelect, onNearbyCancel: onCancel))
    }

    func updateUIViewController(_ controller: UIHostingController<CatalogLibraryView>, context: Context) { }
}
