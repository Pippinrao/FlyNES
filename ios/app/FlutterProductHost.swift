#if FLYNES_FLUTTER
import Flutter
import SwiftUI
import UniformTypeIdentifiers

struct FlutterProductView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> FlutterProductHost { .shared }
    func updateUIViewController(_ controller: FlutterProductHost, context: Context) {}
}

/// One engine and one reusable Flutter controller. Native owners outlive UI routes.
final class FlutterProductHost: UIViewController, UIDocumentPickerDelegate {
    static let shared = FlutterProductHost()
    private static let engines = NSHashTable<FlutterEngine>.weakObjects()
    private static func createEngine() -> FlutterEngine {
        let value = FlutterEngine(name: "flynes.product")
        engines.add(value)
        return value
    }
    private let engine = FlutterProductHost.createEngine()
    private var flutter: FlutterViewController!
    private var channel: FlutterMethodChannel!
    private var service: FlyNesProductService!
    private var current: UIViewController?
    private var game: RunSurfaceViewController?
    private var nearby: UIViewController?
    private var launchReturn: FlyNesProductCompletion?
    private var nearbyReturn: FlyNesProductCompletion?
    private var pickerReturn: FlyNesProductCompletion?
    private var nearbySelectionTimer: Timer?
    private var route = "hall"
    private var purpose = "single"
    private var returnToken = ""
    private var presentationToken = ""
    private var cover: UIView?
    private var observations: [NSObjectProtocol] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 18/255, green: 19/255, blue: 22/255, alpha: 1)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        service = FlyNesProductService(bridge: FlyNesAppBridge.sharedInstance(),
            sources: CatalogSourceService.sharedInstance(), defaults: .standard,
            bundle: .main, documentsRoot: documents)
        presentationToken = UUID().uuidString
        _ = service.activateContext(context())
        // The messenger accepts handlers only after run. This main-thread setup
        // completes before queued Dart platform messages are dispatched.
        guard engine.run() else { showEngineFailure(); return }
        channel = FlutterMethodChannel(name: "flynes/product.v1", binaryMessenger: engine.binaryMessenger)
        service.platformHandler = { [weak self] method, args, completion in
            guard let self else { completion(nil, "service_unavailable"); return }
            self.platform(method, args: args, completion: completion)
        }
        service.eventHandler = { [weak self] method, event in self?.channel.invokeMethod(method, arguments: event) }
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self, let arguments = call.arguments as? [String: Any] else {
                result(FlutterError(code: "invalid_arguments", message: nil, details: nil)); return
            }
            self.service.handleMethod(call.method, arguments: arguments) { body, failure in
                if let failure { result(FlutterError(code: failure, message: nil, details: nil)) }
                else { result(body) }
            }
        }
        flutter = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        flutter.view.backgroundColor = view.backgroundColor
        flutter.view.accessibilityIdentifier = "flutter_product_surface"
        engine.ensureSemanticsEnabled()
        replace(with: flutter, retainImage: false)
        observe("flynes.nearby.pickerRequest") { [weak self] _ in self?.showNearbyPicker() }
        observe("flynes.product.playbackDiagnostics") { [weak self] _ in self?.writeDiagnostics() }
    }

    private func observe(_ name: String, action: @escaping (Notification) -> Void) {
        observations.append(NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil,
            queue: .main, using: action))
    }

    private func context() -> [String: Any] {
        ["route": route, "purpose": purpose, "returnToken": returnToken, "presentationToken": presentationToken]
    }

    private func replace(with next: UIViewController, retainImage: Bool) {
        guard current !== next else { return }
        if next !== flutter {
            nearbySelectionTimer?.invalidate(); nearbySelectionTimer = nil
        }
        let snapshot = retainImage ? current?.view.snapshotView(afterScreenUpdates: false) : nil
        if let old = current {
            old.willMove(toParent: nil)
            old.beginAppearanceTransition(false, animated: false)
            old.view.removeFromSuperview()
            old.endAppearanceTransition()
            old.removeFromParent()
            // Reuse this one controller's engine association. UIKit disappearance
            // pauses rendering, and removing its view releases the visible host.
            // Clearing engine.viewController also destroys the iOS semantics bridge;
            // reassigning the same controller does not rebuild that bridge on 3.38.
        }
        current = next
        addChild(next)
        next.beginAppearanceTransition(true, animated: false)
        next.view.frame = view.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(next.view)
        next.didMove(toParent: self)
        next.endAppearanceTransition()
        cover?.removeFromSuperview()
        cover = snapshot
        if let snapshot {
            snapshot.frame = view.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            snapshot.isUserInteractionEnabled = false
            snapshot.accessibilityElementsHidden = true
            view.addSubview(snapshot)
        }
        writeDiagnostics()
    }

    private func showFlutter(route: String, purpose: String = "single", token: String = "") {
        self.route = route; self.purpose = purpose; returnToken = token
        presentationToken = UUID().uuidString
        replace(with: flutter, retainImage: true)
        _ = service.activateContext(context())
    }

    private func showEngineFailure() {
        let label = UILabel(frame: view.bounds)
        label.numberOfLines = 0; label.textAlignment = .center; label.textColor = .white
        label.text = FlyNesLocalizedString("flutter.initialization_failed")
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
    }

    private func platform(_ method: String, args: [String: Any], completion: @escaping FlyNesProductCompletion) {
        switch method {
        case "presentationReady":
            guard args["token"] as? String == presentationToken,
                  (args["frameNumber"] as? NSNumber)?.intValue ?? 0 > 0 else {
                completion(nil, "stale_host"); return
            }
            cover?.removeFromSuperview(); cover = nil
            writeDiagnostics()
            completion(["accepted": true], nil)
        case "launch": launch(args, completion: completion)
        case "openNative":
            switch args["page"] as? String {
            case "layout": openLayout(completion)
            case "nearby": openNearby(completion)
            default: completion(nil, "invalid_arguments")
            }
        case "pickSource":
            guard pickerReturn == nil, presentedViewController == nil else { completion(nil, "busy"); return }
            pickerReturn = completion
            let picker = UIDocumentPickerViewController(forOpeningContentTypes:
                args["kind"] as? String == "folder" ? [.folder] : [.data], asCopy: false)
            picker.delegate = self; picker.allowsMultipleSelection = false
            present(picker, animated: true)
        case "closeHost":
            guard (route == "settings" && game != nil) || (purpose == "nearby" && nearby != nil) else {
                completion(["status": "returned"], nil); return
            }
            service.deactivateContext()
            presentationToken = UUID().uuidString
            completion(["status": "returned"], nil)
            if route == "settings", let game {
                game.reloadProductSettings(); replace(with: game, retainImage: false)
            } else if purpose == "nearby", let nearby {
                replace(with: nearby, retainImage: false)
                NotificationCenter.default.post(name: Notification.Name("flynes.nearby.pickerClose"), object: nil)
            }
        case "copyText":
            guard let text = args["text"] as? String else { completion(nil, "invalid_arguments"); return }
            UIPasteboard.general.string = text; completion(["status": "completed"], nil)
        case "openLink":
            guard let raw = args["url"] as? String, let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                completion(nil, "invalid_arguments"); return
            }
            UIApplication.shared.open(url) { opened in completion(opened ? ["status": "completed"] : nil, opened ? nil : "service_unavailable") }
        case "previewHaptics":
            previewHaptics()
            completion(["status": "completed"], nil)
        default: completion(nil, "service_unavailable")
        }
    }

    private func launch(_ args: [String: Any], completion: @escaping FlyNesProductCompletion) {
        guard current === flutter, route == "hall" else { completion(nil, "stale_host"); return }
        guard let canonical = args["canonicalId"] as? String, let rom = args["romData"] as? Data,
              !rom.isEmpty else { completion(nil, "launch_failed"); return }
        if purpose == "nearby" {
            let owner = FlyNesNearbyBridge.sharedInstance
            guard nearby != nil, (owner.snapshot()["role"] as? NSNumber)?.intValue == 1 else {
                completion(nil, "stale_host"); return
            }
            let selectionToken = presentationToken
            owner.selectHostGameROM(rom, canonicalID: canonical, title: args["title"] as? String ?? "") { [weak self] selected in
                guard let self, self.presentationToken == selectionToken, self.current === self.flutter else {
                    completion(nil, "stale_host"); return
                }
                completion(selected ? ["status": "returned"] : nil, selected ? nil : "launch_failed")
                guard selected, let nearby = self.nearby else { return }
                self.service.deactivateContext()
                self.replace(with: nearby, retainImage: false)
                NotificationCenter.default.post(name: Notification.Name("flynes.nearby.pickerClose"), object: nil)
            }
            return
        }
        guard game == nil, launchReturn == nil else { completion(nil, "busy"); return }
        let controller = RunSurfaceViewController()
        controller.canonicalId = canonical; controller.romData = rom
        controller.gameTitle = args["title"] as? String ?? ""
        controller.gameTitleFields = args["titleFields"] as? [String: String]
        controller.onPauseCommand = { [weak self] command in
            guard let self else { return }
            if command == "settings" { self.showFlutter(route: "settings", token: self.returnToken) }
            else if command == "game_center" { self.finishGame() }
        }
        returnToken = UUID().uuidString
        game = controller; launchReturn = completion
        replace(with: controller, retainImage: false)
    }

    private func finishGame() {
        let completion = launchReturn; launchReturn = nil
        showFlutter(route: "hall") // native disappearance durably saves before refresh
        game = nil
        completion?(["status": "returned"], nil)
        service.invalidateDomains(["catalog", "resume"])
        writeDiagnostics()
    }

    private func openLayout(_ completion: @escaping FlyNesProductCompletion) {
        guard presentedViewController == nil else { completion(nil, "busy"); return }
        var returned = false
        let tag = UserDefaults.standard.string(forKey: "FlyNesLocaleTag") ?? "system"
        let content = NavigationStack { ControlLayoutEditorView() }
            .environment(\.locale, tag == "system" ? .autoupdatingCurrent : Locale(identifier: tag))
            .onDisappear { [weak self] in
            guard !returned, let self else { return }; returned = true
            self.service.invalidateDomains(["settings"])
            completion(["status": "returned"], nil)
        }
        let controller = UIHostingController(rootView: content)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    private func openNearby(_ completion: @escaping FlyNesProductCompletion) {
        guard nearby == nil else { completion(nil, "busy"); return }
        nearbyReturn = completion
        let controller = UIHostingController(rootView: ProductNearbyFlow(onClose: { [weak self] in self?.finishNearby() }))
        controller.overrideUserInterfaceStyle = .dark
        nearby = controller; replace(with: controller, retainImage: false)
    }

    private func finishNearby() {
        let completion = nearbyReturn; nearbyReturn = nil
        showFlutter(route: "hall"); nearby = nil
        completion?(["status": "returned"], nil)
        service.invalidateDomains(["catalog", "resume"])
    }

    private func showNearbyPicker() {
        guard nearby != nil, current === nearby,
              (FlyNesNearbyBridge.sharedInstance.snapshot()["role"] as? NSNumber)?.intValue == 1 else { return }
        showFlutter(route: "hall", purpose: "nearby", token: UUID().uuidString)
        // The room view is detached while Flutter selects a game. Keep the
        // existing owner's Continue and disconnect intents observable.
        nearbySelectionTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.current === self.flutter, self.purpose == "nearby",
                  self.presentedViewController == nil, let nearby = self.nearby else { return }
            let snapshot = FlyNesNearbyBridge.sharedInstance.snapshot()
            let state = (snapshot["state"] as? NSNumber)?.intValue ?? 0
            let disconnected = state == 0 || state == 4
            let continued = state == 6 && !((snapshot["paused"] as? NSNumber)?.boolValue ?? true)
            guard disconnected || continued else { return }
            self.service.deactivateContext()
            self.replace(with: nearby, retainImage: false)
            NotificationCenter.default.post(name: Notification.Name(disconnected
                ? "flynes.nearby.disconnected" : "flynes.nearby.pickerClose"), object: nil)
        }
        nearbySelectionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let completion = pickerReturn; pickerReturn = nil
        completion?(["status": "cancelled"], nil)
    }

    private func previewHaptics() {
        let settings = FlyNesAppBridge.sharedInstance().settingsGet()
        let level = (settings["haptic_level"] as? NSNumber)?.intValue ?? 1
        guard level > 1 else { return }
        let distinct = (settings["distinct_ab_haptics"] as? NSNumber)?.boolValue ?? false
        let intensity: CGFloat = level == 2 ? 0.4 : level == 4 ? 1.0 : 0.7
        let style: UIImpactFeedbackGenerator.FeedbackStyle = level == 2 ? .light : level == 4 ? .heavy : .medium
        UIImpactFeedbackGenerator(style: distinct ? .rigid : style).impactOccurred(intensity: intensity)
        let token = presentationToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
            guard let self, self.presentationToken == token, self.current === self.flutter else { return }
            UIImpactFeedbackGenerator(style: distinct ? .soft : style).impactOccurred(intensity: intensity)
        }
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let completion = pickerReturn; pickerReturn = nil
        guard let url = urls.first else { completion?(["status": "cancelled"], nil); return }
        completion?(["url": url], nil)
    }

    private func writeDiagnostics() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-flynes.test.product_diagnostics") else { return }
        var result = game?.productDiagnostics() ?? [:]
        result["engineCount"] = Self.engines.allObjects.count
        result["activeFlutterViews"] = Self.engines.allObjects.filter {
            $0.viewController?.viewIfLoaded?.window != nil
        }.count
        result["coreOwnerCount"] = FlyNesRuntimeBridge.liveRuntimeCount()
        result["nearbyPickerObserverCount"] = nearbySelectionTimer?.isValid == true ? 1 : 0
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("product-host-diagnostics.json")
        if let data = try? JSONSerialization.data(withJSONObject: result) { try? data.write(to: path, options: .atomic) }
        #endif
    }
}

private enum ProductNearbyRoute: Hashable { case lobby, play(UInt64) }
private struct ProductNearbyFlow: View {
    let onClose: () -> Void
    @State private var path = NavigationPath()
    @State private var activeGeneration: UInt64?
    @State private var pickerShown = false
    @AppStorage("FlyNesLocaleTag") private var localeTag = "system"
    // Match the existing room owner's atomic path replacement. In particular,
    // a native playback generation must not remain mounted during a transition.
    private func setPath(game generation: UInt64?) {
        activeGeneration = generation
        var next = NavigationPath()
        next.append(ProductNearbyRoute.lobby)
        if let generation { next.append(ProductNearbyRoute.play(generation)) }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { path = next }
    }
    private func trace(_ event: String, generation: UInt64 = 0) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["FLYNES_UI_NEARBY_ROLE"] != nil else { return }
        NSLog("FlyNesProductNearby %@ generation=%llu active=%llu picker=%d", event,
              generation, activeGeneration ?? 0, pickerShown ? 1 : 0)
        #endif
    }
    var body: some View {
        NavigationStack(path: $path) {
            NearbyFriendsView().toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.done", action: onClose)
                }
            }.navigationDestination(for: ProductNearbyRoute.self) { item in
                switch item {
                case .lobby: NearbyLobbyView()
                case .play(let generation): NearbyRunGameContainer(playbackGeneration: generation)
                }
            }
        }
        .environment(\.locale, localeTag == "system" ? .autoupdatingCurrent : Locale(identifier: localeTag))
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.connected"))) { _ in setPath(game: nil) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.leaveRoom"))) { _ in activeGeneration = nil; path = NavigationPath(); onClose() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.disconnected"))) { _ in
            activeGeneration = nil; pickerShown = false
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { path = NavigationPath() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.pickerRequest"))) { _ in pickerShown = true }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.pickerClose"))) { _ in trace("pickerClose"); pickerShown = false; setPath(game: nil) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.playRequest"))) { notification in
            guard !pickerShown, let generation = (notification.object as? NSNumber)?.uint64Value,
                  generation != activeGeneration else { return }
            let owner = FlyNesNearbyBridge.sharedInstance
            guard owner.playbackGeneration == generation,
                  (owner.snapshot()["state"] as? NSNumber)?.intValue == 6,
                  !((owner.snapshot()["paused"] as? NSNumber)?.boolValue ?? true) else { return }
            trace("playRequest", generation: generation)
            setPath(game: generation)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("flynes.nearby.playClosed"))) { notification in
            trace("playClosed", generation: (notification.object as? NSNumber)?.uint64Value ?? 0)
            guard let generation = (notification.object as? NSNumber)?.uint64Value, generation == activeGeneration else { return }
            setPath(game: nil)
        }
    }
}
#endif
