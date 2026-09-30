package com.flynes.emu;

import static org.junit.Assert.*;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.core.app.ActivityScenario;
import androidx.test.platform.app.InstrumentationRegistry;
import android.view.accessibility.AccessibilityNodeInfo;
import android.os.SystemClock;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Runs in the production package on the explicitly selected task AVD. */
@RunWith(AndroidJUnit4.class)
public class FlutterFoundationIntegrationTest {
    @Test public void recreatedHostsIgnoreOldActivityRouteResults() throws Exception {
        InstrumentationRegistry.getInstrumentation().getUiAutomation();
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        var oldHost = new java.util.concurrent.atomic.AtomicReference<FlutterFoundationActivity>();
        var response = new java.util.concurrent.CompletableFuture<Object>();
        try (ActivityScenario<FlutterFoundationActivity> host = ActivityScenario.launch(FlutterFoundationActivity.class)) {
            assertNotNull(awaitNode("launch-selected", true));
            host.onActivity(oldHost::set);
            host.recreate();
            assertNotNull(awaitNode("launch-selected", true));
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> app.foundationBridge().onMethodCall(
                    new io.flutter.plugin.common.MethodCall("openNative", java.util.Map.of("page", "settings")),
                    new io.flutter.plugin.common.MethodChannel.Result() {
                        public void success(Object value) { response.complete(value); }
                        public void error(String code, String message, Object details) { response.completeExceptionally(new AssertionError(code)); }
                        public void notImplemented() { response.completeExceptionally(new AssertionError("Missing native route")); }
                    }));
            assertTrue(awaitActivity(SettingsActivity.class));
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> oldHost.get().onActivityResult(
                    FoundationBridge.NATIVE_ROUTE, android.app.Activity.RESULT_OK, null));
            assertFalse("A stale host must not complete the current host's route", response.isDone());
            InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK);
            response.get(10, java.util.concurrent.TimeUnit.SECONDS);
            assertNotNull(awaitNode("launch-selected", true));
        }
    }
    @Test public void twentyRealGameRoundTripsReleaseAudioAndHistoryTimer() throws Exception {
        InstrumentationRegistry.getInstrumentation().getUiAutomation();
        boolean diagnose = "true".equals(InstrumentationRegistry.getArguments().getString("foundationHeapDiagnostic"));
        var weakGames = new java.util.ArrayList<java.lang.ref.WeakReference<MainActivity>>();
        try (ActivityScenario<FlutterFoundationActivity> host = ActivityScenario.launch(FlutterFoundationActivity.class)) {
            for (int cycle = 0; cycle < 20; cycle++) {
                click(awaitNode("launch-selected", true));
                assertNotNull(awaitNode("pause_button", true));
                MainActivity game = playingActivity();
                weakGames.add(new java.lang.ref.WeakReference<>(game));
                var clockField = MainActivity.class.getDeclaredField("historyClock");
                clockField.setAccessible(true);
                var clock = (com.flynes.emu.save.HistoryClock) clockField.get(game);
                long before = clock.playedMs();
                long deadline = SystemClock.uptimeMillis() + 5000;
                while (clock.playedMs() <= before && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(25);
                assertTrue("Real core/audio sampling advances each cycle", clock.playedMs() > before);
                assertEquals("Only one native audio clock may run", 1, audioThreads());
                click(awaitNode("pause_button", true));
                click(awaitNode("pause_game_center", true));
                assertNotNull(awaitNode("launch-selected", true));
                deadline = SystemClock.uptimeMillis() + 5000;
                while ((!game.isDestroyed() || audioThreads() != 0) && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(25);
                assertTrue("Game owner destroyed after return", game.isDestroyed());
                assertEquals("No native audio clock remains after return", 0, audioThreads());
                var handlerField = MainActivity.class.getDeclaredField("statusHandler");
                var timerField = MainActivity.class.getDeclaredField("historyTimer");
                handlerField.setAccessible(true); timerField.setAccessible(true);
                assertFalse("No save timer remains after return", ((android.os.Handler) handlerField.get(game))
                        .hasCallbacks((Runnable) timerField.get(game)));
                android.util.Log.i("FoundationTest", "ROUNDTRIP cycle=" + (cycle + 1)
                        + " progressed=true audioThreads=0 historyTimer=false");
                if (diagnose) {
                    System.gc(); System.runFinalization(); SystemClock.sleep(100);
                    android.util.Log.i("FoundationTest", "HEAP cycle=" + (cycle + 1) + " weakGames="
                            + weakGames.stream().filter(reference -> reference.get() != null).count()
                            + " used=" + (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()));
                }
            }
            long deadline = SystemClock.uptimeMillis() + 10000;
            long retained;
            do {
                System.gc(); System.runFinalization(); SystemClock.sleep(100);
                retained = weakGames.stream().filter(reference -> reference.get() != null).count();
            } while (retained > 1 && SystemClock.uptimeMillis() < deadline);
            // The current Java test frame may keep its final local alive, never prior games.
            assertTrue("Destroyed game Activities must be collectible; retained=" + retained, retained <= 1);
            android.util.Log.i("FoundationTest", "ROUNDTRIP completed=20 retainedGameOwners=" + retained);
        }
    }

    static long audioThreads() {
        return Thread.getAllStackTraces().keySet().stream().filter(AudioThread.class::isInstance)
                .filter(Thread::isAlive).count();
    }
    @Test public void sharedPageLaunchesNativeGameAndPauseReturnsWithRealHead() throws Exception {
        var automation = InstrumentationRegistry.getInstrumentation().getUiAutomation();
        var info = automation.getServiceInfo();
        info.flags |= android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
        automation.setServiceInfo(info);
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        try (ActivityScenario<FlutterFoundationActivity> scenario = ActivityScenario.launch(FlutterFoundationActivity.class)) {
            click(awaitNode("launch-selected", true));
            assertNotNull("Existing native game must be visible", awaitNode("pause_button", true));
            String id = playingCanonicalId();
            assertEquals("cancelled", launchStatus(app, "missing-content"));
            SystemClock.sleep(1600);
            screenshot("foundation-native-play.png");
            click(awaitNode("pause_button", true));
            assertNotNull("Native pause boundary completed", awaitNode("pause_game_center", true));
            screenshot("foundation-native-pause.png");
            assertEquals("available", ((java.util.Map<?, ?>) app.foundationBridge().resumeCapability(id)).get("state"));
            click(awaitNode("pause_game_center", true));
            assertNotNull("Pause library action must return to the shared Flutter page",
                    awaitNode("foundation-library", true));
            var launch = awaitNode("launch-selected", true);
            assertNotNull("Returned page must finish refreshing its head", launch);
            assertTrue("Returned action must use real history head",
                    String.valueOf(launch.getContentDescription()).matches("Continue|继续"));
            screenshot("foundation-returned.png");
            scenario.recreate();
            assertNotNull("Application engine survives host recreation", awaitNode("launch-selected", true));
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED);
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED);
            assertNotNull("Returning from background refreshes existing engine", awaitNode("launch-selected", true));
            assertEquals("unavailable", launchStatus(app, "missing-content"));
            assertNotNull("Failed launch leaves the shared page usable", awaitNode("launch-selected", true));
            assertNativeHomeContinue(app, id);
        }
    }
    static String playingCanonicalId() {
        try {
            var field = MainActivity.class.getDeclaredField("currentCoverGameId");
            field.setAccessible(true);
            return (String) field.get(playingActivity());
        } catch (Exception failure) { throw new AssertionError(failure); }
    }
    static MainActivity playingActivity() {
        var result = new java.util.concurrent.atomic.AtomicReference<MainActivity>();
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            var activity = androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                    .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED).stream()
                    .filter(MainActivity.class::isInstance).findFirst().orElseThrow();
            result.set((MainActivity) activity);
        });
        return result.get();
    }

    static void assertNativeHomeContinue(FlyNesApplication app, String id) {
        var prefs = app.getSharedPreferences("game_center_ui", Context.MODE_PRIVATE);
        var before = prefs.getAll();
        prefs.edit().putString("category", "ALL").putString("query", "").putString("selected", id).commit();
        try (ActivityScenario<HomeActivity> home = ActivityScenario.launch(HomeActivity.class)) {
            // Tap the real row: a partial startup cache may not restore the requested selection.
            app.catalogRuntime().nativeReady().join();
            assertNotNull(awaitNode("launch_selected", true));
            var rows = app.catalogRuntime().gameCenterSnapshot().rows();
            int position = -1;
            for (int index = 0; index < rows.size(); index++) if (rows.get(index).canonicalId().equals(id)) position = index;
            assertTrue("Played canonical ID is still in native catalog", position >= 0);
            androidx.test.espresso.Espresso.onView(androidx.test.espresso.matcher.ViewMatchers.withId(R.id.game_grid))
                    .perform(androidx.test.espresso.contrib.RecyclerViewActions.actionOnItemAtPosition(
                            position, androidx.test.espresso.action.ViewActions.click()));
            long deadline = SystemClock.uptimeMillis() + 10000;
            var text = new java.util.concurrent.atomic.AtomicReference<String>("");
            do {
                home.onActivity(activity -> {
                    android.widget.TextView launch = activity.findViewById(R.id.launch_selected);
                    if (launch != null) text.set(launch.getText().toString());
                });
                if (app.getString(R.string.continue_selected_game).equals(text.get())) break;
                SystemClock.sleep(100);
            } while (SystemClock.uptimeMillis() < deadline);
            assertEquals("Native hall must resolve the same core history identity",
                    app.getString(R.string.continue_selected_game), text.get());
        } finally {
            var edit = prefs.edit();
            for (String key : new String[] {"category", "query", "selected"}) {
                if (before.containsKey(key)) edit.putString(key, (String) before.get(key)); else edit.remove(key);
            }
            edit.commit();
        }
    }

    static String launchStatus(FlyNesApplication app, String id) throws Exception {
        var response = new java.util.concurrent.CompletableFuture<Object>();
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> app.foundationBridge().onMethodCall(
                new io.flutter.plugin.common.MethodCall("launch", java.util.Map.of("canonicalId", id)),
                new io.flutter.plugin.common.MethodChannel.Result() {
                    public void success(Object result) { response.complete(result); }
                    public void error(String code, String message, Object details) { response.completeExceptionally(new AssertionError(code)); }
                    public void notImplemented() { response.completeExceptionally(new AssertionError("Missing launch")); }
                }));
        return (String) ((java.util.Map<?, ?>) response.get(10, java.util.concurrent.TimeUnit.SECONDS)).get("status");
    }

    @Test public void nativeSettingsSourcesAndNearbyReturnToSharedPage() {
        var automation = InstrumentationRegistry.getInstrumentation().getUiAutomation();
        var info = automation.getServiceInfo();
        info.flags |= android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
        automation.setServiceInfo(info);
        try (ActivityScenario<FlutterFoundationActivity> scenario = ActivityScenario.launch(FlutterFoundationActivity.class)) {
            assertNotNull(awaitNode("launch-selected", true));
            String[] labels = {"Settings", "Game sources", "Nearby play"};
            Class<?>[] pages = {SettingsActivity.class, HomeActivity.class, NearbyFriendsActivity.class};
            for (int index = 0; index < labels.length; index++) {
                click(awaitNode(labels[index], true));
                assertTrue("Existing native page must open: " + labels[index], awaitActivity(pages[index]));
                if (index == 1) assertNotNull("Real source management panel is visible", awaitNode("source_content", true));
                InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK);
                assertNotNull("Native route must complete on return", awaitNode("launch-selected", true));
            }
        }
    }

    static boolean awaitActivity(Class<?> type) {
        long deadline = SystemClock.uptimeMillis() + 10000;
        var found = new java.util.concurrent.atomic.AtomicBoolean();
        do {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> found.set(
                    androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                    .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED).stream().anyMatch(type::isInstance)));
            if (found.get()) return true;
            SystemClock.sleep(100);
        } while (SystemClock.uptimeMillis() < deadline);
        return false;
    }

    static void click(AccessibilityNodeInfo node) {
        assertNotNull("Expected actionable UI node", node);
        String selector=node.getViewIdResourceName();
        if(selector==null||selector.isEmpty())selector=String.valueOf(node.getContentDescription());
        if(java.util.Set.of("Start","Continue","开始","继续").contains(selector))selector="launch-selected";
        var automation=InstrumentationRegistry.getInstrumentation().getUiAutomation();
        try {automation.waitForIdle(200,5000);}catch(java.util.concurrent.TimeoutException busy){throw new AssertionError("UI never reached an actionable semantic frame",busy);}
        // Flutter can replace its disabled button while head refresh completes.
        // Resolve a fresh semantic node after quiescence, not its retired node ID.
        node=awaitNode(selector,true);
        assertNotNull("Current actionable node must remain available: "+selector,node);
        assertTrue("UI action accepted for "+selector+": "+node, node.performAction(AccessibilityNodeInfo.ACTION_CLICK));
    }
    @Test public void sharedFlutterPageLoadsNativeCatalog() {
        var automation = InstrumentationRegistry.getInstrumentation().getUiAutomation();
        var info = automation.getServiceInfo();
        info.flags |= android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
        automation.setServiceInfo(info);
        Context context = ApplicationProvider.getApplicationContext();
        Intent intent = new Intent().setComponent(new ComponentName(context,
                "com.flynes.emu.FlutterFoundationActivity"));
        try (ActivityScenario<?> scenario = ActivityScenario.launch(intent)) {
            var launch = awaitNode("launch-selected", true);
            screenshot("foundation-catalog.png");
            assertNotNull("Flutter page must show an enabled real game launch action", launch);
        }
    }
    static void dump(AccessibilityNodeInfo node) {
        if (node == null) return;
        android.util.Log.i("FoundationTest", node.toString());
        for (int index = 0; index < node.getChildCount(); index++) dump(node.getChild(index));
    }
    static void screenshot(String name) {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync();
        SystemClock.sleep(250); // Let the compositor present the state whose semantics were awaited.
        var bitmap = InstrumentationRegistry.getInstrumentation().getUiAutomation().takeScreenshot();
        Context context = ApplicationProvider.getApplicationContext();
        try (var out = new java.io.FileOutputStream(new java.io.File(context.getExternalFilesDir(null), name))) {
            assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out));
        } catch (Exception failure) { throw new AssertionError(failure); }
        finally { bitmap.recycle(); }
    }

    static AccessibilityNodeInfo awaitNode(String id, boolean enabled) {
        long deadline = SystemClock.uptimeMillis() + 20000;
        do {
            var root = InstrumentationRegistry.getInstrumentation().getUiAutomation().getRootInActiveWindow();
            var found = find(root, id, enabled);
            if (found != null) return found;
            SystemClock.sleep(100);
        } while (SystemClock.uptimeMillis() < deadline);
        return null;
    }
    static AccessibilityNodeInfo find(AccessibilityNodeInfo node, String id, boolean enabled) {
        if (node == null) return null;
        String name = node.getViewIdResourceName();
        boolean primaryLabel = id.equals("launch-selected") && "android.widget.Button".contentEquals(node.getClassName())
                && java.util.Set.of("Start", "Continue", "开始", "继续").contains(String.valueOf(node.getContentDescription()));
        if (name != null && name.endsWith(id) && id.equals("launch-selected")) {
            var button = actionable(node);
            if (button != null && (!enabled || button.isEnabled())) return button;
        } else if ((name != null && name.endsWith(id) || primaryLabel || id.contentEquals(String.valueOf(node.getContentDescription())))
                && (!enabled || node.isEnabled())) return node;
        for (int index = 0; index < node.getChildCount(); index++) {
            var found = find(node.getChild(index), id, enabled);
            if (found != null) return found;
        }
        return null;
    }
    static AccessibilityNodeInfo actionable(AccessibilityNodeInfo node) {
        if (node.isClickable()) return node;
        for (int index = 0; index < node.getChildCount(); index++) {
            var child = node.getChild(index);
            if (child == null) continue;
            var found = actionable(child);
            if (found != null) return found;
        }
        return null;
    }
    @Test public void productionPackageContainsFoundationHost() {
        Context context = ApplicationProvider.getApplicationContext();
        Intent intent = new Intent().setComponent(new ComponentName(context,
                "com.flynes.emu.FlutterFoundationActivity"));
        assertNotNull("Production package must register the Flutter foundation host",
                context.getPackageManager().resolveActivity(intent, 0));
        assertEquals("com.flynes.emu", context.getPackageName());
    }
}
