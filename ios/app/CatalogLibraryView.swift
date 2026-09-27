import SwiftUI
import UIKit

private struct AccessibleNativeSwitch: UIViewRepresentable {
    @Binding var isOn: Bool
    let identifier: String
    let label: String

    final class Coordinator: NSObject {
        var parent: AccessibleNativeSwitch

        init(_ parent: AccessibleNativeSwitch) {
            self.parent = parent
        }

        @objc func changed(_ sender: UISwitch) {
            parent.isOn = sender.isOn
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISwitch {
        let control = UISwitch(frame: .zero)
        control.accessibilityIdentifier = identifier
        control.accessibilityLabel = label
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)),
                          for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UISwitch, context: Context) {
        context.coordinator.parent = self
        if control.isOn != isOn {
            control.setOn(isOn, animated: false)
        }
    }
}

enum LibraryRoute: Hashable {
    /// The resolved ROM travels with the route, so reaching the run screen already
    /// means the game could be opened.
    case run(canonicalId: String, rom: Data, game: CatalogGame)
    /// 附近联机. A real destination, and the only route on this screen that does not
    /// need a ROM: the nearby pages exist to render the exact stage that blocks them.
    case nearby
    case nearbyLobby
    case nearbyGamePicker
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case recent = "RECENT", favorites = "FAVORITES", all = "ALL", builtin = "BUILTIN"
    var id: String { rawValue }
    var titleKey: LocalizedStringKey {
        switch self {
        case .recent: return "game_center.recent"
        case .favorites: return "game_center.favorites"
        case .all: return "game_center.all"
        case .builtin: return "game_center.builtin"
        }
    }
}

/// Shared, versioned two-player capability projection (design 2026-09-13 §3.2).
/// The only legal source of two-player eligibility: never inferred from file
/// names, "P2" in a title, or controller counts. Unread ids and entries whose
/// profile version mismatches project UNKNOWN, never UNSUPPORTED.
enum MultiplayerEligibility: UInt8 {
    case unsupported = 0
    case supported = 1
    case unknown = 2
}

struct MultiplayerCapabilityRegistry {
    let profileVersion: UInt32
    private var entries: [String: (eligibility: MultiplayerEligibility, version: UInt32)] = [:]
    init(profileVersion: UInt32) {
        self.profileVersion = profileVersion
    }

    mutating func put(_ canonicalId: String, _ eligibility: MultiplayerEligibility,
                      _ version: UInt32) {
        entries[canonicalId] = (eligibility, version)
    }

    func eligibilityFor(_ canonicalId: String) -> MultiplayerEligibility {
        guard let entry = entries[canonicalId], entry.version == profileVersion else {
            return .unknown
        }
        return entry.eligibility
    }
}

/// Populated by the ObjC++ bridge from the shared versioned profile projection
/// (P6); never from local file inspection.
enum MultiplayerCapabilitySource {
    static var registry: MultiplayerCapabilityRegistry = loadSharedRegistry()

    static func reload() {
        registry = loadSharedRegistry()
    }

    private static func loadSharedRegistry() -> MultiplayerCapabilityRegistry {
        let games = FlyNesBuiltinGames.shared()
        let version = UInt32(max(0, games.multiplayerProfileVersion))
        var result = MultiplayerCapabilityRegistry(profileVersion: version)
        for game in games.all() {
            let eligibility: MultiplayerEligibility
            switch game.multiplayerEligibility {
            case "SUPPORTED": eligibility = .supported
            case "UNSUPPORTED": eligibility = .unsupported
            default: eligibility = .unknown
            }
            result.put(game.canonicalId, eligibility, UInt32(max(0, game.multiplayerProfileVersion)))
        }
        return result
    }
}

/// Mirrors Android HomeActivity: selected detail on the left, two-row horizontal
/// card grid on the right. Selecting a card never navigates away from the grid.
struct CatalogLibraryView: View {
    private let nearbySelection: ((CatalogGame, Data) -> Bool)?
    private let onNearbyCancel: (() -> Void)?
    private let testStartInHostLobby: Bool
    private let testStartInNearbyEntry: Bool
    @State private var snapshot: CatalogSnapshot
    @State private var cachedRows: [[String: Any]] = []
    @AppStorage("GameCenterCategory") private var category = LibraryFilter.all.rawValue
    @AppStorage("GameCenterQuery") private var searchText = ""
    // Independent two-player filter (design U04): persisted per device, never
    // changed by category, query, or connection events.
    @AppStorage("GameCenterMultiplayerOnly") private var multiplayerOnly = false
    @AppStorage("GameCenterSelected.ALL") private var allSelection = ""
    @AppStorage("GameCenterSelected.RECENT") private var recentSelection = ""
    @AppStorage("GameCenterSelected.FAVORITES") private var favoriteSelection = ""
    @AppStorage("GameCenterSelected.BUILTIN") private var builtinSelection = ""
    @State private var searchOpen = false
    @FocusState private var searchFocused: Bool
    @State private var sourcesOpen = false
    @State private var settingsOpen = false
    @State private var nearbySelectionFailed = false
    @State private var path = NavigationPath()
    @State private var enteringLobby = false
    @State private var pickerShown = false
    @State private var testRouteOpened = false
    @State private var navigationEpoch = 0
    @ObservedObject private var sources = CatalogSourceModel.shared
    @ObservedObject private var covers = GameCoverModel.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    init(snapshot: CatalogSnapshot = CatalogSnapshot(generation: 0, games: []),
         nearbySelection: ((CatalogGame, Data) -> Bool)? = nil,
         onNearbyCancel: (() -> Void)? = nil,
         testStartInHostLobby: Bool = false,
         testStartInNearbyEntry: Bool = false) {
        _snapshot = State(initialValue: snapshot)
        self.nearbySelection = nearbySelection
        self.onNearbyCancel = onNearbyCancel
        self.testStartInHostLobby = testStartInHostLobby
        self.testStartInNearbyEntry = testStartInNearbyEntry
    }

    private var largeText: Bool { typeSize.isAccessibilitySize }
    private var selectedID: String {
        get {
            switch LibraryFilter(rawValue: category) ?? .all {
            case .all: return allSelection
            case .recent: return recentSelection
            case .favorites: return favoriteSelection
            case .builtin: return builtinSelection
            }
        }
        nonmutating set {
            switch LibraryFilter(rawValue: category) ?? .all {
            case .all: allSelection = newValue
            case .recent: recentSelection = newValue
            case .favorites: favoriteSelection = newValue
            case .builtin: builtinSelection = newValue
            }
        }
    }
    private var compactHeader: Bool { largeText || locale.identifier == "en_XA" }
    private var selectedGame: CatalogGame? { snapshot.games.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                if searchOpen {
                    HStack {
                        TextField("library.search", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($searchFocused)
                            .onSubmit { searchFocused = false }
                            .accessibilityIdentifier("search_input")
                        icon("xmark", "common.cancel", "close_search") {
                            searchFocused = false; searchText = ""; searchOpen = false
                        }
                    }.frame(minHeight: 56)
                }
                if sourcesOpen {
                    CatalogSourceManagementView(onClose: { sourcesOpen = false })
                } else {
                    GeometryReader { geometry in
                        HStack(spacing: 8) {
                            CatalogGameDetailView(game: selectedGame, largeText: largeText,
                                                  cover: selectedGame.flatMap { covers.image(for: $0.id) },
                                                  onLaunch: launch)
                                .frame(width: max(0, (geometry.size.width - 8) * 0.3))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .center, spacing: 12) {
                                    status.lineLimit(2).frame(minHeight: 48, alignment: .leading)
                                    Spacer(minLength: 0)
                                    HStack(spacing: 8) {
                                        Text("nearby.filter.multiplayerOnly")
                                            .lineLimit(2)
                                        AccessibleNativeSwitch(
                                            isOn: $multiplayerOnly,
                                            identifier: "nearby_multiplayer_filter",
                                            label: FlyNesLocalizedString("nearby.filter.multiplayerOnly")
                                        )
                                        .fixedSize()
                                    }
                                    .frame(minHeight: 48)
                                }
                                ScrollView(.horizontal) {
                                    LazyHGrid(rows: Array(repeating: GridItem(.flexible(), spacing: 8),
                                                         count: largeText ? 1 : 2), spacing: 8) {
                                        ForEach(snapshot.games) { game in
                                            Button { selectedID = game.id } label: {
                                                CatalogGameRow(game: game, selected: selectedID == game.id,
                                                               largeText: largeText,
                                                               cover: covers.image(for: game.id))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("game_card_" + game.id)
                                        }
                                    }.padding(4)
                                }
                                .accessibilityIdentifier("game_grid")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .run(let id, let rom, let game): RunGameContainer(canonicalId: id, romData: rom, game: game, path: $path)
                case .nearby:
                    if nearbySelection == nil {
                        NearbyFriendsView()
                    } else {
                        EmptyView()
                    }
                case .nearbyLobby:
                    NearbyLobbyView(testHostLobby: ProcessInfo.processInfo.arguments.contains(
                        "-flynes.test.nearby_host_lobby_route") || ProcessInfo.processInfo.arguments.contains(
                        "-flynes.test.nearby_role_connected"))
                case .nearbyGamePicker:
                    NearbyCatalogPicker(onSelect: { game, rom in
                        guard pickerShown else { return false }
                        let selected = FlyNesNearbyBridge.sharedInstance.selectHostGameROM(
                            rom, canonicalID: game.id, title: game.titlePrimary)
                        if selected {
                            NotificationCenter.default.post(name: Notification.Name("flynes.nearby.pickerClose"), object: nil)
                        }
                        return selected
                    }, onCancel: {
                        NotificationCenter.default.post(name: Notification.Name("flynes.nearby.pickerClose"), object: nil)
                    })
                }
            }
            .fullScreenCover(isPresented: $settingsOpen) { SettingsView() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.connected"))) { _ in
                if nearbySelection == nil { showNearbyLobby() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.leaveRoom"))) { _ in
                guard nearbySelection == nil else { return }
                enteringLobby = false
                pickerShown = false
                path = NavigationPath()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.disconnected"))) { _ in
                guard nearbySelection == nil else { return }
                enteringLobby = false
                pickerShown = false
                var nextPath = NavigationPath()
                nextPath.append(LibraryRoute.nearby)
                path = nextPath
                navigationEpoch += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.pickerRequest"))) { _ in
                guard nearbySelection == nil && enteringLobby && !pickerShown else { return }
                pickerShown = true
                path.append(LibraryRoute.nearbyGamePicker)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.pickerClose"))) { _ in
                guard nearbySelection == nil && pickerShown else { return }
                pickerShown = false
                path = NavigationPath()
                path.append(LibraryRoute.nearbyLobby)
            }
            .onAppear {
                searchOpen = !searchText.isEmpty
                sources.initialize()
                MultiplayerCapabilitySource.reload()
                reloadSnapshot()
                if testStartInHostLobby && !testRouteOpened {
                    testRouteOpened = true
                    showNearbyLobby()
                } else if testStartInNearbyEntry && !testRouteOpened {
                    testRouteOpened = true
                    path.append(LibraryRoute.nearby)
                }
            }
            .onReceive(sources.$generation) { _ in reloadSnapshot() }
            .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                guard nearbySelection == nil && pickerShown else { return }
                let snapshot = FlyNesNearbyBridge.sharedInstance.snapshot()
                if (snapshot["state"] as? NSNumber)?.intValue == 6 &&
                    !((snapshot["paused"] as? NSNumber)?.boolValue ?? true) {
                    pickerShown = false
                    path = NavigationPath()
                    path.append(LibraryRoute.nearbyLobby)
                }
            }
            .onChange(of: category) { _ in sourcesOpen = false; reloadSnapshot() }
            .onChange(of: searchText) { _ in reloadSnapshot() }
            .onChange(of: multiplayerOnly) { _ in reloadSnapshot() }
            .onChange(of: locale) { _ in reprojectTitles() }
        }
        .id(navigationEpoch)
    }

    private func showNearbyLobby() {
        guard !enteringLobby else { return }
        enteringLobby = true
        DispatchQueue.main.async {
            path = NavigationPath()
            path.append(LibraryRoute.nearbyLobby)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if !compactHeader {
                Text("game_center.title").font(.headline).lineLimit(1)
                    .accessibilityAddTraits(.isHeader).padding(.trailing, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(LibraryFilter.allCases) { item in
                        Button {
                            category = item.rawValue
                            sourcesOpen = false
                        } label: {
                            Text(item.titleKey).lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 72, minHeight: largeText ? 64 : 48)
                                .foregroundColor(category == item.rawValue ? .white : .primary)
                                .background(category == item.rawValue ? Color.accentColor : Color.clear)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("category_" + item.rawValue.lowercased())
                        .accessibilityAddTraits(category == item.rawValue ? .isSelected : [])
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            icon("magnifyingglass", "library.search", "open_search") { searchOpen = true; sourcesOpen = false }
            icon("folder", "library.sources", "open_sources") { sourcesOpen = true }
            icon("gearshape", "settings.title", "open_settings") { settingsOpen = true }
            if let onNearbyCancel {
                Button("nearby.lobby.title", action: onNearbyCancel)
                    .frame(minHeight: 48)
                    .accessibilityIdentifier("nearby_library_return_to_room")
            } else {
                Button {
                    sourcesOpen = false
                    searchOpen = false
                    let state = (FlyNesNearbyBridge.sharedInstance.snapshot()["state"] as? NSNumber)?.intValue ?? 0
                    if state == 3 || state == 5 || state == 6 || state == 7 {
                        showNearbyLobby()
                    } else {
                        path.append(LibraryRoute.nearby)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text("nearby.open")
                            .lineLimit(1)
                            .accessibilityIdentifier("nearby_entry_text")
                    }
                    .frame(minHeight: 48)
                }
                .accessibilityIdentifier("open_nearby")
            }
        }.frame(height: largeText ? 80 : 64)
    }

    @ViewBuilder private var status: some View {
        if nearbySelectionFailed {
            Text("nearby.localGameMissing").foregroundColor(.red)
        } else if sources.busy {
            HStack { ProgressView(); Text("library.source.working") }
        } else if let launching = sources.launching {
            HStack { ProgressView(); Text(String(format: FlyNesLocalizedString("library.launching_game"), launching)) }
        } else if let error = sources.error {
            Text(error).foregroundColor(.red)
        } else if snapshot.games.isEmpty {
            Text(searchText.isEmpty ? "library.no_games" : "library.search.empty")
                .foregroundColor(.secondary)
        } else if sources.sources.isEmpty {
            Text("library.source.add_hint").foregroundColor(.secondary)
        } else {
            Text(String(format: FlyNesLocalizedString("library.game_count"), snapshot.games.count))
                .foregroundColor(.secondary)
        }
    }

    private func icon(_ image: String, _ label: LocalizedStringKey, _ id: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).frame(width: 48, height: 48) }
            .accessibilityLabel(Text(label)).accessibilityIdentifier(id)
    }

    /// Android resolves and commits the selected game before leaving the Game
    /// Center; a failure is reported in the status line with the grid still visible.
    private func launch(_ game: CatalogGame) {
        nearbySelectionFailed = false
        sources.launch(canonicalID: game.id, title: game.titlePrimary) { rom in
            if let nearbySelection {
                nearbySelectionFailed = !nearbySelection(game, rom)
            } else {
                path.append(LibraryRoute.run(canonicalId: game.id, rom: rom, game: game))
            }
        }
    }

    private func reloadSnapshot() {
        var rows = FlyNesAppBridge.sharedInstance().gameCenterFilteredGames(
            forCategory: LibraryFilter(rawValue: category)?.rawValue ?? "ALL", query: searchText)
        if multiplayerOnly {
            // Stable post-filter: removes non-SUPPORTED rows only, never re-sorts.
            rows = rows.filter { row in
                guard let canonicalId = row["canonicalId"] as? String else { return false }
                return MultiplayerCapabilitySource.registry.eligibilityFor(canonicalId) == .supported
            }
        }
        cachedRows = rows
        reprojectTitles()
        covers.preload(canonicalIds: snapshot.games.map(\.id))
    }

    private func reprojectTitles() {
        let games = cachedRows.compactMap { CatalogGameFactory.game(from: $0, localeIdentifier: locale.identifier) }
        snapshot = CatalogSnapshot(generation: snapshot.generation &+ 1, games: games)
        if !games.contains(where: { $0.id == selectedID }) { selectedID = games.first?.id ?? "" }
    }
}
