package com.flynes.emu;

import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import com.flynes.emu.cover.AndroidCoverRepository;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Process-owned narrow UI adapter. It borrows catalog, history and launch owners. */
final class FoundationBridge implements MethodChannel.MethodCallHandler {
    static final int NATIVE_ROUTE = 7101;
    static final String RETURN_TO_FOUNDATION = "return_to_foundation";
    private final FlyNesApplication app;
    private final AndroidCoverRepository covers;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread thread = new Thread(r, "flynes-foundation-query");
        thread.setDaemon(true);
        return thread;
    });
    private long generation;
    private FlutterFoundationActivity host;
    private MethodChannel.Result pending;
    private boolean pendingLaunch;

    FoundationBridge(FlyNesApplication app) {
        this.app = app;
        covers = new AndroidCoverRepository(app);
    }

    void attach(FlutterFoundationActivity activity) { host = activity; }
    void detach(FlutterFoundationActivity activity) {
        if (host != activity) return;
        host = null;
        if (activity.isFinishing()) complete("cancelled");
    }
    void returned(FlutterFoundationActivity activity) {
        if (activity == host) complete("returned");
    }

    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "catalogSnapshot" -> query(result, this::catalogSnapshot);
            case "resumeCapability" -> {
                String id = argument(call, "canonicalId");
                if (id == null) result.error("invalid_argument", "Canonical ID required", null);
                else query(result, () -> resumeCapability(id));
            }
            case "launch" -> launch(argument(call, "canonicalId"), result);
            case "openNative" -> openNative(argument(call, "page"), result);
            default -> result.notImplemented();
        }
    }

    private static String argument(MethodCall call, String name) {
        Object value = call.argument(name);
        return value instanceof String text && !text.isBlank() ? text : null;
    }

    private void query(MethodChannel.Result result, Callable<Object> operation) {
        worker.execute(() -> {
            try {
                Object value = operation.call();
                main.post(() -> result.success(value));
            } catch (Exception failure) {
                main.post(() -> result.error("native_unavailable", "Native query unavailable", null));
            }
        });
    }

    Object catalogSnapshot() throws Exception {
        app.catalogRuntime().nativeReady().get();
        var games = new ArrayList<Map<String, Object>>();
        for (var row : app.catalogRuntime().gameCenterSnapshot().rows()) {
            games.add(Map.of("canonicalId", row.canonicalId(), "titleEn", row.titleEn(),
                    "titleZhHans", row.titleZhHans(), "available", row.launchable(),
                    "unavailableReason", row.launchable() ? "" : "Game source unavailable",
                    "coverPath", covers.existingPath(row.canonicalId())));
        }
        return Map.of("generation", ++generation, "games", games);
    }

    Object resumeCapability(String id) throws Exception {
        return app.resumeService().query(id);
    }

    private void launch(String id, MethodChannel.Result result) {
        if (id == null) { result.error("invalid_argument", "Canonical ID required", null); return; }
        if (!begin(result, true)) return;
        app.gameLaunchService().launchCanonical(id, launch -> {
            if (pending != result) {
                launch.request().ifPresent(PendingGameLaunch::discard);
                return;
            }
            if (!launch.sessionCommitted() || host == null || host.isFinishing()) {
                launch.request().ifPresent(PendingGameLaunch::discard);
                pending = null;
                result.success(Map.of("status", "unavailable", "reason", "Unable to start this game"));
                return;
            }
            if (!open(new Intent(host, MainActivity.class).putExtra(RETURN_TO_FOUNDATION, true)))
                launch.request().ifPresent(PendingGameLaunch::discard);
        });
    }

    private void openNative(String page, MethodChannel.Result result) {
        Class<?> destination = page == null ? null : switch (page) {
            case "settings" -> SettingsActivity.class;
            case "sources" -> HomeActivity.class;
            case "nearby" -> NearbyFriendsActivity.class;
            default -> null;
        };
        if (destination == null) { result.error("invalid_argument", "Unknown native page", null); return; }
        if (begin(result, false)) {
            Intent intent = new Intent(host, destination);
            if ("sources".equals(page)) intent.setAction(HomeActivity.ACTION_SHOW_SOURCES)
                    .putExtra(RETURN_TO_FOUNDATION, true);
            open(intent);
        }
    }

    private boolean begin(MethodChannel.Result result, boolean launch) {
        if (pending != null || host == null || host.isFinishing()) {
            if (launch) result.success(Map.of("status", "cancelled", "reason", "Native route busy"));
            else result.error("native_busy", "Native route unavailable", null);
            return false;
        }
        pending = result;
        pendingLaunch = launch;
        return true;
    }

    private boolean open(Intent intent) {
        try { host.startActivityForResult(intent, NATIVE_ROUTE); return true; }
        catch (RuntimeException failure) {
            MethodChannel.Result result = pending;
            pending = null;
            if (pendingLaunch) result.success(Map.of("status", "unavailable", "reason", "Unable to open game"));
            else result.error("native_unavailable", "Unable to open native page", null);
            return false;
        }
    }

    private void complete(String status) {
        MethodChannel.Result result = pending;
        pending = null;
        if (result != null) result.success(pendingLaunch ? Map.of("status", status) : null);
    }
}
