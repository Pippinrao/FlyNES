import SwiftUI
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
    @State private var showGame = false
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

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 12) {
                field("nearby.lobby.network_owner", value: "P1",
                      identifier: "nearby_lobby_row_network_owner")
                field("nearby.lobby.seat", value: role == 1 ? "P1" : "P2",
                      identifier: "nearby_lobby_row_seat")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("nearby.lobby.rom_identity")
                    .nearbyRole(NearbyTypography.sectionTitle)
                    .foregroundStyle(ink)
                    .accessibilityIdentifier("nearby_lobby_row_rom_identity")
                if role == 1 {
                    Button(gameTitle.isEmpty ? FlyNesLocalizedString("nearby.chooseGame") : gameTitle) {
                        let bridge = FlyNesNearbyBridge.sharedInstance
                        if state == 5 {
                            pendingPicker = bridge.returnLobby()
                        } else {
                            NotificationCenter.default.post(name: Notification.Name("flynes.nearby.pickerRequest"), object: nil)
                        }
                    }
                    .disabled(state != 3 && state != 5)
                    .nearbyRole(NearbyTypography.body)
                    .accessibilityIdentifier("nearby_lobby_choose_game")
                } else {
                    Text(gameError ? "nearby.localGameMissing" :
                         (gameTitle.isEmpty ? "nearby.waitHostGame" : gameTitle))
                        .nearbyRole(NearbyTypography.muted)
                        .foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                Text(gameError ? "nearby.localGameMissing" :
                     (localReady ? (peerReady ? "nearby.status.starting" : "nearby.status.waitingPeer") :
                      (state == 3 || state == 7 ? "nearby.screen.connected" : "nearby.status.matchingGame")))
                    .nearbyRole(NearbyTypography.muted)
                    .foregroundStyle(muted)
                    .accessibilityIdentifier("nearby_lobby_confirm_reason")
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .navigationDestination(isPresented: $showGame) {
            NearbyRunGameContainer()
        }
        .onAppear { if !testHostLobby { refresh() } }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            if !testHostLobby { refresh() }
        }
    }

    private func refresh() {
        let bridge = FlyNesNearbyBridge.sharedInstance
        let snapshot = bridge.snapshot()
        state = (snapshot["state"] as? NSNumber)?.intValue ?? 0
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
                let row = FlyNesAppBridge.sharedInstance().catalogSnapshotGames()
                    .first { ($0["canonicalId"] as? String) == peerKey }
                guard let row else { gameError = true; return }
                let title = (row["titleEn"] as? String) ?? peerKey
                CatalogSourceModel.shared.prepareROM(peerKey) { result in
                    guard loadingConfigToken == configToken,
                          (bridge.snapshot()["peerConfigToken"] as? String) == configToken else { return }
                    switch result {
                    case .success(let rom):
                        if bridge.selectGuestGameROM(rom, canonicalID: peerKey, title: title) {
                            gameTitle = title
                            gameError = false
                        } else { gameError = true }
                    case .failure: gameError = true
                    }
                    loadingConfigToken = ""
                }
            }
        }
        if state == 6 { showGame = true }
    }

    private func endRoom() {
        guard !ended else { return }
        ended = true
        NotificationCenter.default.post(name: Notification.Name("flynes.nearby.disconnected"), object: nil)
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
        let onSelect: (CatalogGame, Data) -> Bool
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIHostingController<CatalogLibraryView> {
        UIHostingController(rootView: CatalogLibraryView(
            nearbySelection: onSelect, onNearbyCancel: onCancel))
    }

    func updateUIViewController(_ controller: UIHostingController<CatalogLibraryView>, context: Context) { }
}
