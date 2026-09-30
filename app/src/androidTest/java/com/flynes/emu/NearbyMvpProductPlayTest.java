package com.flynes.emu;

import android.content.Intent;
import android.os.SystemClock;
import android.view.MotionEvent;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.platform.app.InstrumentationRegistry;
import com.flynes.emu.catalog.GameCatalogEntry;
import com.flynes.emu.catalog.GameVariant;
import com.flynes.emu.catalog.BuiltinGames;
import com.flynes.emu.input.GamepadHitMap;
import org.junit.Test;
import java.io.File;
import java.nio.file.Files;
import java.util.concurrent.TimeUnit;
import static org.junit.Assert.*;
import static androidx.test.espresso.Espresso.onView;
import static androidx.test.espresso.action.ViewActions.click;
import static androidx.test.espresso.action.ViewActions.scrollTo;
import static androidx.test.espresso.matcher.ViewMatchers.withId;

/** Opt-in local acceptance. User ROMs stay in the existing catalog, never fixtures. */
public final class NearbyMvpProductPlayTest {
    private android.net.ConnectivityManager redirectedNetwork;
    private android.net.Network previousNetwork;

    @org.junit.After public void restoreTestNetworkBinding() {
        if (redirectedNetwork != null) redirectedNetwork.bindProcessToNetwork(previousNetwork);
    }

    @Test public void hostUsesProductControls() throws Exception {
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        var args = InstrumentationRegistry.getArguments();
        String query = args.getString("localGameQuery", "");
        String firstTitle;
        String gameKey;
        if (query.isEmpty()) {
            NearbyMvpGame.Selection selection = NearbyMvpGame.load(app);
            firstTitle = selection.entry.titleEn;
            gameKey = selection.entry.canonicalId;
        }
        else {
            app.catalogRuntime().bootstrap().get(30, TimeUnit.SECONDS);
            GameVariant selected = null;
            String selectedKey = null;
            for (GameCatalogEntry entry : app.catalogRuntime().gameCatalog().canonicalEntries()) {
                for (GameVariant candidate : entry.variants()) {
                    if (candidate.isLaunchable() && candidate.originalFilename().equals(query)) {
                        selected = candidate;
                        selectedKey = entry.canonicalGame().id();
                        break;
                    }
                }
                if (selected != null) break;
            }
            assertNotNull("Requested local catalog game is absent", selected);
            firstTitle = query.replaceFirst("\\.[^.]+$", "");
            gameKey = selectedKey;
        }
        String bindAddress = NearbyMvpLanAddress.current();
        String redirectedAddress = args.getString("emulatorRedirectBindAddress", "");
        if (!redirectedAddress.isEmpty()) {
            assertTrue("NAT binding override is emulator instrumentation only",
                    android.os.Build.HARDWARE.equals("ranchu") || android.os.Build.HARDWARE.equals("goldfish"));
            assertEquals("Android emulator redir targets its Ethernet guest address", "10.0.2.15", redirectedAddress);
            assertNotNull("Redirect target must be assigned on this emulator",
                    java.net.NetworkInterface.getByInetAddress(java.net.InetAddress.getByName(redirectedAddress)));
            redirectedNetwork = app.getSystemService(android.net.ConnectivityManager.class);
            previousNetwork = redirectedNetwork.getBoundNetworkForProcess();
            android.net.Network targetNetwork = null;
            for (android.net.Network network : redirectedNetwork.getAllNetworks()) {
                var properties = redirectedNetwork.getLinkProperties(network);
                if (properties != null && properties.getLinkAddresses().stream().anyMatch(
                        address -> redirectedAddress.equals(address.getAddress().getHostAddress()))) {
                    targetNetwork = network;
                    break;
                }
            }
            assertNotNull("Redirect needs an Android Network for return traffic", targetNetwork);
            assertTrue("Bind the test process to the redirect's Network for its return path",
                    redirectedNetwork.bindProcessToNetwork(targetNetwork));
            bindAddress = redirectedAddress;
        }
        assertTrue(app.nearbyMvpOwner().startHost(bindAddress));
        NearbyMvpSession session = app.nearbyMvpOwner().session();
        long deadline = SystemClock.elapsedRealtime() + 30_000;
        String invite;
        do { invite = session.invite(); SystemClock.sleep(20); }
        while (invite == null && SystemClock.elapsedRealtime() < deadline);
        assertNotNull("No invitation", invite);
        Files.write(new File(app.getFilesDir(), "nearby-cross-invite.txt").toPath(),
                invite.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        while (session.snapshot()[0] != NearbyMvpSession.LOBBY && SystemClock.elapsedRealtime() < deadline)
            SystemClock.sleep(20);
        assertEquals(NearbyMvpSession.LOBBY, session.snapshot()[0]);
        byte[] connectedId = session.sessionId();
        try (ActivityScenario<NearbyLobbyActivity> room = ActivityScenario.launch(NearbyLobbyActivity.class)) {
            onView(withId(R.id.nearby_lobby_choose_game)).perform(click());
            chooseFlutterGame(firstTitle, query.isEmpty());
            waitState(session, NearbyMvpSession.RUNNING);
            assertSame("Chooser must retain the original room owner", session, app.nearbyMvpOwner().session());
            assertArrayEquals(connectedId, session.sessionId());
            assertEquals("Chooser must preserve the existing nearby wire identity", gameKey, app.nearbyMvpOwner().gameKey());
            if (query.isEmpty()) {
                var chosen = BuiltinGames.fromAssets(app).all().stream().filter(entry -> entry.titleEn.equals(firstTitle)).findFirst().orElseThrow();
                assertTrue("First chooser must launch the requested game", app.nearbyMvpOwner().gameTitle().equals(chosen.titleEn)
                        || app.nearbyMvpOwner().gameTitle().equals(chosen.titleZhHans));
            } else assertEquals(gameKey, app.nearbyMvpOwner().gameKey());
            gameKey = app.nearbyMvpOwner().gameKey();
            awaitActivity(MainActivity.class);
            SystemClock.sleep(6000);
            for (GamepadHitMap.Control control : new GamepadHitMap.Control[] {
                    GamepadHitMap.Control.START, GamepadHitMap.Control.SELECT,
                    GamepadHitMap.Control.START, GamepadHitMap.Control.START,
                    GamepadHitMap.Control.A, GamepadHitMap.Control.B,
                    GamepadHitMap.Control.RIGHT }) {
                long down = SystemClock.uptimeMillis();
                float[] point = new float[2];
                onGame(activity -> {
                    GamepadView pad = activity.findViewById(R.id.gamepad);
                    var target = pad.hitMapForTest().target(control);
                    int[] origin = new int[2];
                    pad.getLocationOnScreen(origin);
                    point[0] = origin[0] + target.centerX();
                    point[1] = origin[1] + target.centerY();
                });
                touch(down, MotionEvent.ACTION_DOWN, point);
                onGame(activity -> {
                    GamepadView pad = activity.findViewById(R.id.gamepad);
                    assertTrue("Real touch was not accepted: " + control, pad.buttons() != 0);
                });
                SystemClock.sleep(150);
                int expected = control == GamepadHitMap.Control.START ? 8 :
                        control == GamepadHitMap.Control.SELECT ? 4 :
                        control == GamepadHitMap.Control.A ? 1 : control == GamepadHitMap.Control.B ? 2 : 128;
                assertEquals("Touch must reach a completed P1 core frame", expected, session.snapshot()[9]);
                touch(down, MotionEvent.ACTION_UP, point);
                SystemClock.sleep(control == GamepadHitMap.Control.START ? 1200 : 150);
            }
            long before = session.completedFrames();
            SystemClock.sleep(2000);
            assertTrue("Product loop did not advance", session.completedFrames() > before + 30);
            onGame(activity -> {
                long samples = activity.nearbyAudioWrittenSamplesForTest();
                assertTrue("Android must submit nearby PCM to AudioTrack", samples > 4800);
                try {
                    var playField = MainActivity.class.getDeclaredField("nearbyPlay");
                    playField.setAccessible(true);
                    var audioField = NearbyMvpPlayController.class.getDeclaredField("audio");
                    audioField.setAccessible(true);
                    android.media.AudioTrack track = (android.media.AudioTrack) audioField.get(playField.get(activity));
                    assertNotNull("Native nearby AudioTrack exists", track);
                    long played = Integer.toUnsignedLong(track.getPlaybackHeadPosition());
                    assertTrue("Android AudioTrack must actually play nearby PCM", played > 4800);
                    android.util.Log.i("FlyNesNearby", "event=product_audio written_samples=" + samples
                            + " playback_frames=" + played);
                } catch (ReflectiveOperationException failure) { throw new AssertionError(failure); }
            });
            long hold = Long.parseLong(args.getString("playHoldMs", "0"));
            if (hold > 0) SystemClock.sleep(hold);
            onView(withId(R.id.pause_button)).perform(click());
            SystemClock.sleep(250);
            long paused = session.completedFrames();
            SystemClock.sleep(2400);
            assertEquals("Pause must freeze the core without disconnecting", paused, session.completedFrames());
            assertEquals(NearbyMvpSession.RUNNING, session.snapshot()[0]);
            onView(withId(R.id.pause_continue)).perform(click());
            SystemClock.sleep(800);
            assertTrue("Resume must advance the same game", session.completedFrames() > paused + 10);
            onView(withId(R.id.pause_button)).perform(click());
            onView(withId(R.id.pause_game_center)).perform(scrollTo(), click());
            waitState(session, NearbyMvpSession.RUNNING);
            SystemClock.sleep(700);
            long roomFrame = session.completedFrames();
            SystemClock.sleep(600);
            assertEquals("Room must retain paused progress", roomFrame, session.completedFrames());
            assertEquals(gameKey, app.nearbyMvpOwner().gameKey());
            onView(withId(R.id.nearby_lobby_resume)).perform(click());
            SystemClock.sleep(1200);
            assertTrue("Room continue must resume original progress", session.completedFrames() > roomFrame + 10);
            assertArrayEquals(connectedId, session.sessionId());
            onView(withId(R.id.pause_button)).perform(click());
            onView(withId(R.id.pause_game_center)).perform(scrollTo(), click());
            SystemClock.sleep(700);
            onView(withId(R.id.nearby_lobby_choose_game)).perform(click());
            BuiltinGames.Entry nextGame = null;
            for (BuiltinGames.Entry candidate : BuiltinGames.fromAssets(app).all()) {
                if (candidate.multiplayerEligibility == BuiltinGames.MultiplayerEligibility.SUPPORTED
                        && candidate.multiplayerMaxPlayers == 2
                        && !candidate.titleEn.equals(firstTitle)) {
                    nextGame = candidate;
                    break;
                }
            }
            assertNotNull("Need a different playable bundled game", nextGame);
            chooseFlutterGame(nextGame.titleEn, true);
            waitState(session, NearbyMvpSession.RUNNING);
            assertEquals("Guest must resolve the second game through its real catalog", 1, session.snapshot()[6]);
            assertArrayEquals("Changing games must retain the connection", connectedId, session.sessionId());
            assertTrue("The host must play the newly chosen title",
                    app.nearbyMvpOwner().gameTitle().equals(nextGame.titleEn) ||
                    app.nearbyMvpOwner().gameTitle().equals(nextGame.titleZhHans));
            long secondGameDeadline = SystemClock.elapsedRealtime() + 3000;
            while (session.completedFrames() <= 30 &&
                    SystemClock.elapsedRealtime() < secondGameDeadline)
                SystemClock.sleep(20);
            assertTrue("Second game must play", session.completedFrames() > 30);
            android.util.Log.i("FlyNesNearby", "event=product_lobby_switch second_game=PASS");
            if (!query.isEmpty()) {
                onView(withId(R.id.pause_button)).perform(click());
                onView(withId(R.id.pause_game_center)).perform(scrollTo(), click());
                waitState(session, NearbyMvpSession.RUNNING);
                SystemClock.sleep(700);
                onView(withId(R.id.nearby_lobby_choose_game)).perform(click());
                chooseFlutterGame(firstTitle, false);
                waitState(session, NearbyMvpSession.RUNNING);
                assertEquals("Guest must resolve the user ROM from its real catalog", 1, session.snapshot()[6]);
                assertArrayEquals(connectedId, session.sessionId());
                SystemClock.sleep(5000);
                assertTrue(session.completedFrames() > 30);
                android.util.Log.i("FlyNesNearby", "event=product_lobby_switch third_game=PASS");
            }
        }
    }

    private static void waitState(NearbyMvpSession session, int wanted) {
        long deadline = SystemClock.elapsedRealtime() + 15000;
        while (session.snapshot()[0] != wanted && SystemClock.elapsedRealtime() < deadline)
            SystemClock.sleep(20);
        assertEquals("Unexpected session state", wanted, session.snapshot()[0]);
    }

    /** Real accessibility actions against Flutter, never a bridge launch shortcut. */
    static void chooseFlutterGame(String title, boolean builtin) throws Exception {
        awaitActivity(FlutterFoundationActivity.class);
        // The cached hall can retain its open search field between room visits.
        // Wait for the actual chooser semantics, not merely the attached Activity.
        awaitNode(node -> labelMatches(node, "Choose game", "选择游戏"));
        clickFlutter(builtin ? new String[]{"Built-in", "内置"} : new String[]{"All", "全部"});
        recordChooser("before-search", title);
        var existingInput = findNode(InstrumentationRegistry.getInstrumentation().getUiAutomation().getRootInActiveWindow(), node -> node.isEditable());
        android.util.Log.i("FlyNesNearby", "event=flutter_search title=" + title + " retained=" + (existingInput != null));
        if (existingInput == null) clickFlutter("Search", "搜索");
        android.view.accessibility.AccessibilityNodeInfo input = awaitNode(node -> node.isEditable());
        android.os.Bundle text = new android.os.Bundle();
        text.putCharSequence(android.view.accessibility.AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, title);
        assertTrue(input.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_SET_TEXT, text));
        SystemClock.sleep(300);
        var host = awaitActivity(FlutterFoundationActivity.class);
        var keyboard = new java.util.concurrent.atomic.AtomicBoolean();
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            var insets = host.getWindow().getDecorView().getRootWindowInsets();
            keyboard.set(insets != null && insets.isVisible(android.view.WindowInsets.Type.ime()));
        });
        if (keyboard.get()) InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK);
        SystemClock.sleep(400);
        recordChooser("before-launch", title);
        clickFlutter("Choose game", "选择游戏");
        awaitActivity(MainActivity.class);
        android.util.Log.i("FlyNesNearby", "event=flutter_chooser title=" + title + " production_launch=true");
    }

    static void clickFlutter(String... labels) throws Exception {
        var node = awaitNode(candidate -> {
            if (!candidate.isClickable() || !candidate.isEnabled()) return false;
            return labelMatches(candidate, labels);
        });
        assertTrue(node.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK));
    }

    private static boolean labelMatches(android.view.accessibility.AccessibilityNodeInfo node, String... labels) {
        for (String label : labels) if (label.contentEquals(String.valueOf(node.getText()))
                || label.contentEquals(String.valueOf(node.getContentDescription()))) return true;
        return false;
    }

    private static int chooserStep;
    private static void recordChooser(String phase, String title) throws Exception {
        String name = "nearby-chooser-" + (++chooserStep) + "-" + phase;
        var root = InstrumentationRegistry.getInstrumentation().getUiAutomation().getRootInActiveWindow();
        StringBuilder tree = new StringBuilder("title=" + title + "\n");
        appendTree(root, tree, 0);
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        Files.write(new File(app.getExternalFilesDir(null), name + ".txt").toPath(), tree.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
        FlutterFoundationIntegrationTest.screenshot(name + ".png");
    }

    private static void appendTree(android.view.accessibility.AccessibilityNodeInfo node, StringBuilder tree, int depth) {
        if (node == null) return;
        tree.append(" ".repeat(depth)).append(node.toString()).append('\n');
        for (int index = 0; index < node.getChildCount(); index++) appendTree(node.getChild(index), tree, depth + 1);
    }

    private static android.view.accessibility.AccessibilityNodeInfo awaitNode(
            java.util.function.Predicate<android.view.accessibility.AccessibilityNodeInfo> match) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + 15000;
        do {
            var found = findNode(InstrumentationRegistry.getInstrumentation().getUiAutomation().getRootInActiveWindow(), match);
            if (found != null) return found;
            SystemClock.sleep(50);
        } while (SystemClock.elapsedRealtime() < deadline);
        recordChooser("unavailable", "unknown");
        throw new AssertionError("Flutter chooser accessibility control unavailable");
    }

    private static android.view.accessibility.AccessibilityNodeInfo findNode(
            android.view.accessibility.AccessibilityNodeInfo node,
            java.util.function.Predicate<android.view.accessibility.AccessibilityNodeInfo> match) {
        if (node == null) return null;
        if (match.test(node)) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            var found = findNode(node.getChild(i), match); if (found != null) return found;
        }
        return null;
    }

    static <T> T awaitActivity(Class<T> type) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + 30000;
        java.util.concurrent.atomic.AtomicReference<T> found = new java.util.concurrent.atomic.AtomicReference<>();
        do {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                for (var activity : androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED))
                    if (type.isInstance(activity)) found.set(type.cast(activity));
            });
            if (found.get() != null) return found.get();
            SystemClock.sleep(50);
        } while (SystemClock.elapsedRealtime() < deadline);
        throw new AssertionError("Product activity unavailable: " + type.getSimpleName());
    }

    static void onGame(java.util.function.Consumer<MainActivity> action) throws Exception {
        MainActivity activity = awaitActivity(MainActivity.class);
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> action.accept(activity));
    }

    private static void touch(long down, int action, float[] point) {
        MotionEvent event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                point[0], point[1], 0);
        event.setSource(android.view.InputDevice.SOURCE_TOUCHSCREEN);
        InstrumentationRegistry.getInstrumentation().sendPointerSync(event);
        event.recycle();
    }
}
