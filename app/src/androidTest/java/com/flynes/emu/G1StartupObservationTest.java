package com.flynes.emu;

import static org.junit.Assert.*;

import android.app.Activity;
import android.app.Application;
import android.content.Intent;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.Debug;
import android.os.SystemClock;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import androidx.recyclerview.widget.RecyclerView;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import io.flutter.embedding.engine.renderer.FlutterRenderer;
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

/** One instrumented, process-cold sample per invocation; no fixture or production writes. */
@RunWith(AndroidJUnit4.class)
public class G1StartupObservationTest {
    private static final AtomicBoolean SAMPLED = new AtomicBoolean();
    private static final long POLL_MS = 25;

    @Test public void observeOneColdActivity() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        org.junit.Assume.assumeTrue("Explicit observation invocation required",
                "true".equals(args.getString("g1StartupObservation")));
        String route = args.getString("g1StartupRoute", "");
        assertTrue("Route must be native or flutter", route.equals("native") || route.equals("flutter"));
        assertTrue("Exactly one sample per process; invoke am instrument again", SAMPLED.compareAndSet(false, true));
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        var engineField = FlyNesApplication.class.getDeclaredField("foundationEngine");
        engineField.setAccessible(true);
        assertNull("A prewarmed Flutter engine invalidates this cold sample", engineField.get(app));
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> assertTrue("No existing resumed activity",
                androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED).isEmpty()));

        long processStart = android.os.Process.getStartElapsedRealtime();
        JSONObject report = new JSONObject().put("schema", 1).put("route", route)
                .put("pid", android.os.Process.myPid()).put("processStartElapsedRealtimeMs", processStart)
                .put("testEntryElapsedRealtimeMs", now()).put("instrumented", true)
                .put("pollIntervalRequestedMs", POLL_MS)
                .put("scope", "software observation upper bounds; runner/Application startup, UI automation, main-thread dispatch and polling overhead included")
                .put("clock", "SystemClock.elapsedRealtime; process origin Process.getStartElapsedRealtime")
                .put("directoryScope", "native runtime current snapshot count, not Flutter rendered item count")
                .put("result", "incomplete");
        var startup = app.catalogRuntime().startup();
        FutureObservation nativeReady = new FutureObservation(startup.nativeReady());
        FutureObservation projectionReady = new FutureObservation(startup.projectionReady());
        FrameObservation frame = new FrameObservation(app, engineField);
        app.registerActivityLifecycleCallbacks(frame);
        long request = 0, interactive = 0, firstCard = 0;
        int interactiveCount = -1, firstCardCount = -1, polls = 0;
        int[] adapterCount = {-1};
        var preferences = app.getSharedPreferences("game_center_ui", android.content.Context.MODE_PRIVATE);
        var previousPreferences = new java.util.HashMap<String, Object>(preferences.getAll());
        var automation = instrumentation.getUiAutomation();
        var service = automation.getServiceInfo();
        int oldFlags = service.flags;
        service.flags |= android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
        automation.setServiceInfo(service);
        try {
            // The fixture owner supplies the identity once, outside measured processes.
            // Searching for a launchable row here would decode/warm the entire lazy snapshot.
            String selection = args.getString("g1ExpectedSelectedCanonicalId", "");
            assertFalse("Supply independently verified available content for both routes", selection.isEmpty());
            assertTrue(preferences.edit().putString("category", "ALL").putString("query", "")
                    .putBoolean("multiplayerOnly", false).putString("selected", selection).commit());
            report.put("activeFilters", new JSONObject().put("category", "ALL").put("query", "")
                    .put("multiplayerOnly", false)).put("configuredSelectedCanonicalId", selection);
            Intent intent = new Intent(app, route.equals("flutter")
                    ? FlutterFoundationActivity.class : HomeActivity.class);
            request = now();
            report.put("activityRequestElapsedRealtimeMs", request);
            try (ActivityScenario<?> scenario = ActivityScenario.launch(intent)) {
                report.put("activityScenarioReturnedElapsedRealtimeMs", now());
                long deadline = request + 30000;
                while (now() < deadline && (interactive == 0 || firstCard == 0
                        || nativeReady.observed.get() == 0 || projectionReady.observed.get() == 0
                        || route.equals("flutter") && frame.observed.get() == 0)) {
                    polls++;
                    boolean[] visible = new boolean[2];
                    AccessibilityNodeInfo root = automation.getRootInActiveWindow();
                    try {
                        if (route.equals("flutter")) {
                            visible[0] = hasFlutterNode(root, "launch-selected", false);
                            visible[1] = hasFlutterNode(root, "game-card-", true);
                        } else {
                            // Same polling cadence; native controls additionally use actual View conditions.
                            scenario.onActivity(activity -> {
                                View primary = activity.findViewById(R.id.launch_selected);
                                visible[0] = shown(primary) && primary.isEnabled() && primary.hasOnClickListeners();
                                RecyclerView grid = activity.findViewById(R.id.game_grid);
                                adapterCount[0] = grid == null || grid.getAdapter() == null ? -1 : grid.getAdapter().getItemCount();
                                var snapshot = app.catalogRuntime().gameCenterSnapshot();
                                visible[1] = snapshot.fullProjection() && adapterCount[0] == snapshot.rows().size()
                                        && grid != null && grid.getChildCount() > 0 && shown(grid.getChildAt(0));
                            });
                        }
                    } finally { if (root != null) root.recycle(); }
                    if (visible[0] && interactive == 0) {
                        interactive = now();
                        interactiveCount = app.catalogRuntime().gameCenterSnapshot().rows().size();
                    }
                    if (visible[1] && firstCard == 0) {
                        firstCard = now();
                        firstCardCount = app.catalogRuntime().gameCenterSnapshot().rows().size();
                    }
                    if (interactive == 0 || firstCard == 0 || nativeReady.observed.get() == 0
                            || projectionReady.observed.get() == 0
                            || route.equals("flutter") && frame.observed.get() == 0) SystemClock.sleep(POLL_MS);
                }
                assertTrue("Visible enabled primary action must be observed", interactive > 0);
                assertTrue("A visible catalog card must be observed", firstCard > 0);
                assertTrue("Native readiness must complete successfully", nativeReady.observed.get() > 0 && !nativeReady.failed);
                assertTrue("Native full projection must complete successfully", projectionReady.observed.get() > 0 && !projectionReady.failed);
                if (route.equals("flutter")) assertTrue("Renderer first UI must be observed", frame.observed.get() > 0);
                else {
                    assertNull("Native route must not initialize Flutter", engineField.get(app));
                    assertEquals("ALL native adapter must contain the complete snapshot",
                            app.catalogRuntime().gameCenterSnapshot().rows().size(), adapterCount[0]);
                    scenario.onActivity(activity -> {
                        try {
                            var navigationField = HomeActivity.class.getDeclaredField("navigation");
                            navigationField.setAccessible(true);
                            var navigation = (com.flynes.emu.gamecenter.GameCenterState) navigationField.get(activity);
                            assertEquals("The measured action targets the configured content", selection,
                                    navigation.selectedCanonicalId());
                        } catch (ReflectiveOperationException failure) { throw new AssertionError(failure); }
                    });
                }
                report.put("memoryWhileActivityReady", memory()).put("result", "PASS");
            }
        } finally {
            var restore = preferences.edit().clear();
            for (var entry : previousPreferences.entrySet()) {
                Object value = entry.getValue();
                if (value instanceof String) restore.putString(entry.getKey(), (String) value);
                else if (value instanceof Boolean) restore.putBoolean(entry.getKey(), (Boolean) value);
                else if (value instanceof Integer) restore.putInt(entry.getKey(), (Integer) value);
                else if (value instanceof Long) restore.putLong(entry.getKey(), (Long) value);
                else if (value instanceof Float) restore.putFloat(entry.getKey(), (Float) value);
                else if (value instanceof java.util.Set) {
                    @SuppressWarnings("unchecked") var set = (java.util.Set<String>) value;
                    restore.putStringSet(entry.getKey(), set);
                }
            }
            boolean restored = restore.commit() && previousPreferences.equals(preferences.getAll());
            app.unregisterActivityLifecycleCallbacks(frame);
            instrumentation.runOnMainSync(frame::close);
            service.flags = oldFlags;
            automation.setServiceInfo(service);
            report.put("preferencesRestored", restored).put("nativeAdapterCount", adapterCount[0])
                    .put("pollCount", polls).put("primaryInteractive", stamp(interactive, processStart, request))
                    .put("firstVisibleCard", stamp(firstCard, processStart, request))
                    .put("nativeSnapshotCountAtInteractive", interactiveCount)
                    .put("nativeSnapshotCountAtFirstCard", firstCardCount)
                    .put("nativeSnapshotCountAtEnd", app.catalogRuntime().gameCenterSnapshot().rows().size())
                    .put("nativeReady", nativeReady.json(processStart, request))
                    .put("nativeProjectionReady", projectionReady.json(processStart, request))
                    .put("flutterRendererFirstUi", stamp(frame.observed.get(), processStart, request))
                    .put("flutterRendererListenerRegisteredElapsedRealtimeMs", frame.registered)
                    .put("flutterRendererAlreadyDisplayedAtRegistration", frame.alreadyDisplayed)
                    .put("flutterRendererBoundary", frame.alreadyDisplayed
                            ? "registration upper bound; first frame preceded listener" : "renderer UI display callback receipt; not physical presentation")
                    .put("memoryAfterActivityClosed", memory());
            File directory = app.getExternalFilesDir(null);
            assertNotNull("External evidence directory", directory);
            File file = new File(directory, "g1-startup-" + route + "-" + android.os.Process.myPid() + ".json");
            Files.write(file.toPath(), report.toString(2).getBytes(StandardCharsets.UTF_8));
            android.util.Log.i("G1StartupObservation", "report=" + file.getAbsolutePath());
            assertTrue("Restore original UI preferences", restored);
        }
    }

    private static long now() { return SystemClock.elapsedRealtime(); }
    private static boolean shown(View view) {
        Rect bounds = new Rect();
        return view != null && view.isShown() && view.getGlobalVisibleRect(bounds) && !bounds.isEmpty();
    }
    private static boolean hasFlutterNode(AccessibilityNodeInfo node, String id, boolean prefix) {
        if (node == null) return false;
        String resource = node.getViewIdResourceName();
        if (resource != null) {
            String name = resource.substring(resource.lastIndexOf('/') + 1);
            boolean matches = prefix ? name.startsWith(id) : name.equals(id);
            Rect bounds = new Rect();
            node.getBoundsInScreen(bounds);
            if (matches && node.isVisibleToUser() && !bounds.isEmpty()
                    && (prefix || enabledAction(node))) return true;
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            try { if (hasFlutterNode(child, id, prefix)) return true; }
            finally { if (child != null) child.recycle(); }
        }
        return false;
    }
    private static boolean enabledAction(AccessibilityNodeInfo node) {
        if (node.isVisibleToUser() && node.isEnabled() && node.isClickable()) return true;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            try { if (child != null && enabledAction(child)) return true; }
            finally { if (child != null) child.recycle(); }
        }
        return false;
    }
    private static JSONObject stamp(long time, long process, long request) throws Exception {
        return new JSONObject().put("elapsedRealtimeMs", time == 0 ? JSONObject.NULL : time)
                .put("sinceProcessMs", time == 0 ? JSONObject.NULL : time - process)
                .put("sinceActivityRequestMs", time == 0 || request == 0 ? JSONObject.NULL : time - request);
    }
    private static JSONObject memory() throws Exception {
        Debug.MemoryInfo info = new Debug.MemoryInfo();
        Debug.getMemoryInfo(info);
        return new JSONObject().put("observedElapsedRealtimeMs", now()).put("pssKb", info.getTotalPss())
                .put("javaUsedBytes", Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory())
                .put("nativeHeapBytes", Debug.getNativeHeapAllocatedSize());
    }
    private static final class FutureObservation {
        final AtomicLong observed = new AtomicLong();
        final boolean alreadyDone;
        volatile boolean failed;
        FutureObservation(CompletableFuture<?> future) {
            alreadyDone = future.isDone();
            future.whenComplete((value, error) -> { failed = error != null; observed.compareAndSet(0, now()); });
        }
        JSONObject json(long process, long request) throws Exception {
            return stamp(observed.get(), process, request).put("alreadyDoneAtRegistration", alreadyDone)
                    .put("failed", failed).put("boundary", "future callback receipt upper bound, not native completion timestamp");
        }
    }
    private static final class FrameObservation implements Application.ActivityLifecycleCallbacks, FlutterUiDisplayListener {
        final AtomicLong observed = new AtomicLong();
        final FlyNesApplication app;
        final java.lang.reflect.Field engineField;
        FlutterRenderer renderer;
        long registered;
        boolean alreadyDisplayed;
        FrameObservation(FlyNesApplication app, java.lang.reflect.Field engineField) {
            this.app = app;
            this.engineField = engineField;
        }
        private void attach(Activity activity) {
            if (renderer != null || !(activity instanceof FlutterFoundationActivity)) return;
            // FlutterActivity.getFlutterEngine() is protected. Read the existing application
            // owner without calling foundationEngine(), which would initialize it during observation.
            final io.flutter.embedding.engine.FlutterEngine engine;
            try { engine = (io.flutter.embedding.engine.FlutterEngine) engineField.get(app); }
            catch (IllegalAccessException failure) { throw new AssertionError(failure); }
            if (engine == null) return;
            renderer = engine.getRenderer();
            registered = now();
            alreadyDisplayed = renderer.isDisplayingFlutterUi();
            renderer.addIsDisplayingFlutterUiListener(this);
        }
        public void onActivityCreated(Activity activity, Bundle state) { attach(activity); }
        public void onActivityPostCreated(Activity activity, Bundle state) { attach(activity); }
        public void onActivityStarted(Activity activity) { attach(activity); }
        public void onActivityResumed(Activity activity) { }
        public void onActivityPaused(Activity activity) { }
        public void onActivityStopped(Activity activity) { }
        public void onActivitySaveInstanceState(Activity activity, Bundle state) { }
        public void onActivityDestroyed(Activity activity) { }
        public void onFlutterUiDisplayed() { observed.compareAndSet(0, now()); }
        public void onFlutterUiNoLongerDisplayed() { }
        void close() { if (renderer != null) renderer.removeIsDisplayingFlutterUiListener(this); }
    }
}
