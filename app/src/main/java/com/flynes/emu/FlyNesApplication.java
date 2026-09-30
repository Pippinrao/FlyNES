package com.flynes.emu;

import android.app.Application;

import com.flynes.emu.catalog.android.AndroidCatalogRuntime;
import com.flynes.emu.gamecenter.GameCenterStartupTrace;
import com.flynes.emu.settings.ControlLayoutRepository;
import com.flynes.emu.settings.SettingsRepository;

/** Process-scoped owner for the catalog and exact-launch pipeline. */
public final class FlyNesApplication extends Application {
    private AndroidCatalogRuntime catalogRuntime;
    private AndroidGameLaunchService gameLaunchService;
    private NearbyAvailability<NearbySessionOwner> nearbyAvailability;
    private NearbySession nearbySession;
    private NearbyMvpOwner nearbyMvpOwner;
    private final NearbyUiHotspot nearbyUiHotspot = new NearbyUiHotspot();
    private io.flutter.embedding.engine.FlutterEngine foundationEngine;
    private FoundationBridge foundationBridge;
    private ProductBridge productBridge;
    private FlutterFoundationActivity flutterHost;
    private final java.util.Set<FlutterFoundationActivity> flutterHosts=new java.util.HashSet<>();
    private final ProductGameHandoff<MainActivity> gameHandoff=new ProductGameHandoff<>();
    private AndroidResumeService resumeService;

    /** Lazily initialized on the UI thread; the Flutter page does not own native services. */
    public io.flutter.embedding.engine.FlutterEngine foundationEngine() {
        if (foundationEngine == null) {
            foundationEngine = new io.flutter.embedding.engine.FlutterEngine(this);
            foundationBridge = new FoundationBridge(this);
            new io.flutter.plugin.common.MethodChannel(foundationEngine.getDartExecutor().getBinaryMessenger(),
                    "flynes/foundation").setMethodCallHandler(foundationBridge);
            productBridge=new ProductBridge(this,new io.flutter.plugin.common.MethodChannel(
                    foundationEngine.getDartExecutor().getBinaryMessenger(),"flynes/product.v1"));
            foundationEngine.getDartExecutor().executeDartEntrypoint(
                    io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint.createDefault());
        }
        return foundationEngine;
    }
    FoundationBridge foundationBridge() { return foundationBridge; }
    ProductBridge productBridge() { return productBridge; }
    void acquireFlutterHost(FlutterFoundationActivity activity) {
        flutterHosts.add(activity);
        if(flutterHost!=null&&flutterHost!=activity)flutterHost.releaseEngineLease();
        flutterHost=activity;
    }
    void releaseFlutterHost(FlutterFoundationActivity activity) {
        if(!activity.isChangingConfigurations())
            gameHandoff.abandon(activity.getIntent().getStringExtra("native_game_handoff"));
        flutterHosts.remove(activity);if(flutterHost==activity)flutterHost=null;
    }
    void gameDestroyed(MainActivity game){gameHandoff.destroyed(game);}
    android.content.Intent prepareHallHandoff(MainActivity game) {
        return ProductRoutes.intent(game,"hall").putExtra("native_game_handoff",gameHandoff.begin(game));
    }
    void flutterPresented(FlutterFoundationActivity destination) {
        if(flutterHost!=destination)return;
        MainActivity game=gameHandoff.complete(destination.getIntent().getStringExtra("native_game_handoff"));
        if(game==null)return;
        // Dispose the retired hall only after its replacement has a matching raster.
        for(var old:new java.util.ArrayList<>(flutterHosts))if(old!=destination)old.finish();
        if(game!=null){game.finish();game.overridePendingTransition(0,0);}
    }
    AndroidResumeService resumeService() { return resumeService; }

    @Override public void onCreate() {
        super.onCreate();
        GameCenterStartupTrace.event("APPLICATION_CREATE", "phase=begin");
        catalogRuntime = new AndroidCatalogRuntime(this);
        GameCenterStartupTrace.event("APPLICATION_CREATE", "phase=catalog-constructed");
        catalogRuntime.start();
        GameCenterStartupTrace.event("APPLICATION_CREATE", "phase=catalog-started");
        gameLaunchService = new AndroidGameLaunchService(catalogRuntime);
        resumeService = new AndroidResumeService(this);
        nearbyAvailability = new NearbyAvailability<>(NearbyAvailability.fromIllegalState(
                () -> NearbySessionOwner.create(catalogRuntime), "nearby_blocked_session_read"));
        nearbyMvpOwner = new NearbyMvpOwner();
        GameCenterStartupTrace.event("APPLICATION_CREATE", "phase=done");
    }

    public AndroidCatalogRuntime catalogRuntime() { return catalogRuntime; }
    public AndroidGameLaunchService gameLaunchService() { return gameLaunchService; }

    /** Creates the process-scoped V2 owner on first nearby entry. Catalog never calls this. */
    public NearbyAvailability.Status ensureNearby() {
        NearbyAvailability.Status status = nearbyAvailability.ensure();
        if (status.ready() && nearbySession == null) {
            nearbySession = NearbySession.attach(nearbyAvailability.ownerOrNull());
        }
        return status;
    }

    public NearbySession nearbySession() {
        ensureNearby();
        return nearbySession != null ? nearbySession : NearbySession.unavailable();
    }

    public NearbySessionOwner nearbySessionOwner() {
        return nearbyAvailability == null ? null : nearbyAvailability.ownerOrNull();
    }

    public NearbyMvpOwner nearbyMvpOwner() { return nearbyMvpOwner; }
    NearbyUiHotspot nearbyUiHotspot() { return nearbyUiHotspot; }

    public NearbyAvailability.Status nearbyStatus() {
        if (nearbyAvailability == null) {
            return NearbyAvailability.Status.unavailable("nearby_blocked_session_read");
        }
        if (nearbyAvailability.ready()) return NearbyAvailability.Status.ok();
        return NearbyAvailability.Status.unavailable(nearbyAvailability.reasonKey());
    }
    public SettingsRepository settingsRepository() {
        return catalogRuntime == null ? null : catalogRuntime.settingsRepository();
    }

    public ControlLayoutRepository.Backend controlLayoutBackend() {
        return catalogRuntime == null ? null : catalogRuntime.controlLayoutBackend();
    }
}
