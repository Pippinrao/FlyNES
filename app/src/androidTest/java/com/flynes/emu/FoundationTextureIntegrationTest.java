package com.flynes.emu;

import static org.junit.Assert.*;
import android.content.Intent;
import android.graphics.Rect;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import androidx.lifecycle.Lifecycle;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.flynes.emu.flutter.FoundationTextureProbe;
import java.lang.reflect.Field;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Predicate;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Real core/audio/EGL -> Flutter Texture. No user save DB is touched. */
@RunWith(AndroidJUnit4.class)
public class FoundationTextureIntegrationTest {
    @Test public void nativeOwnerHandoffRejectsOldCommandsAndKeepsHostPauseAuthoritative() {
        Intent intent = new Intent(ApplicationProvider.getApplicationContext(), FlutterFoundationActivity.class)
                .putExtra("flutter_texture_probe", true);
        try (ActivityScenario<FlutterFoundationActivity> scenario = ActivityScenario.launch(intent)) {
            await(scenario, state -> number(state, "submittedFrames") > 2);
            scenario.onActivity(activity -> {
                FoundationTextureProbe probe = probe(activity);
                call(probe, "attach", Map.of("owner", "test-old"));
                call(probe, "attach", Map.of("owner", "test-new"));
                long releases = number(probe.snapshot(), "detaches");
                call(probe, "detach", Map.of("owner", "test-old"));
                call(probe, "input", Map.of("owner", "test-old", "buttons", 255));
                call(probe, "active", Map.of("owner", "test-old", "active", false));
                assertEquals(releases, number(probe.snapshot(), "detaches"));
                assertEquals(true, probe.snapshot().get("attached"));
                assertEquals(true, probe.snapshot().get("audioAlive"));
                assertEquals(0L, number(probe.snapshot(), "requestedButtons"));
                probe.setActive(false);
                call(probe, "active", Map.of("owner", "test-new", "active", true));
                assertEquals(false, probe.snapshot().get("audioAlive"));
                call(probe, "detach", Map.of("owner", "test-new"));
                assertEquals(false, probe.snapshot().get("attached"));
                assertEquals(true, probe.snapshot().get("coreAlive"));
            });
        }
    }

    private static FoundationTextureProbe probe(FlutterFoundationActivity activity) {
        try {
            for (Field field : FlutterFoundationActivity.class.getDeclaredFields()) {
                if (field.getType() == FoundationTextureProbe.class) {
                    field.setAccessible(true);
                    return (FoundationTextureProbe) field.get(activity);
                }
            }
        } catch (Exception failure) { throw new AssertionError(failure); }
        throw new AssertionError("Missing probe owner");
    }

    private static void call(FoundationTextureProbe probe, String method, Map<String, Object> args) {
        boolean[] completed = {false};
        probe.onMethodCall(new io.flutter.plugin.common.MethodCall(method, args),
                new io.flutter.plugin.common.MethodChannel.Result() {
                    public void success(Object value) { completed[0] = true; }
                    public void error(String code, String message, Object details) { fail(message); }
                    public void notImplemented() { fail("Missing " + method); }
                });
        assertTrue("Native command must finish synchronously on platform thread", completed[0]);
    }

    @Test public void nativeMediaSurvivesMultiTouchBackgroundAndTwentyTextureCycles() throws Exception {
        var automation = InstrumentationRegistry.getInstrumentation().getUiAutomation();
        Intent intent = new Intent(ApplicationProvider.getApplicationContext(), FlutterFoundationActivity.class)
                .putExtra("flutter_texture_probe", true);
        try (ActivityScenario<FlutterFoundationActivity> scenario = ActivityScenario.launch(intent)) {
            Map<String, Object> initial = await(scenario, state -> number(state, "submittedFrames") >= 20
                    && number(state, "audioPlaybackFrames") > 4800);
            assertEquals(0L, number(initial, "runtimeFailures"));
            assertEquals(true, initial.get("audioAlive"));
            android.util.Log.i("FoundationTextureTest", "initialAudio=" + initial);
            FlutterFoundationIntegrationTest.screenshot("foundation-texture-playing.png");
            FlutterFoundationIntegrationTest.dump(automation.getRootInActiveWindow());
            Rect a = bounds(awaitLabel("A")), b = bounds(awaitLabel("B"));
            long down = SystemClock.uptimeMillis();
            inject(down, MotionEvent.ACTION_DOWN, new Rect[]{a}, new int[]{0});
            inject(down, MotionEvent.ACTION_POINTER_DOWN | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                    new Rect[]{a, b}, new int[]{0, 1});
            await(scenario, state -> number(state, "sampledButtons") == 3);
            inject(down, MotionEvent.ACTION_POINTER_UP, new Rect[]{a, b}, new int[]{0, 1});
            await(scenario, state -> number(state, "sampledButtons") == 2);
            inject(down, MotionEvent.ACTION_CANCEL, new Rect[]{b}, new int[]{1});
            await(scenario, state -> number(state, "sampledButtons") == 0);

            scenario.moveToState(Lifecycle.State.CREATED);
            Map<String, Object> paused = snapshot(scenario);
            assertEquals(false, paused.get("audioAlive"));
            assertEquals(0L, number(paused, "requestedButtons"));
            long stoppedUs = number(paused, "playedUs");
            SystemClock.sleep(300);
            assertEquals("Background must not advance emulation", stoppedUs, number(snapshot(scenario), "playedUs"));
            scenario.moveToState(Lifecycle.State.RESUMED);
            await(scenario, state -> number(state, "playedUs") > stoppedUs + 100000);

            for (int cycle = 1; cycle <= 20; cycle++) {
                click("Detach");
                final int count = cycle;
                Map<String, Object> detached = await(scenario, state -> number(state, "detaches") == count);
                assertEquals(false, detached.get("audioAlive"));
                assertEquals(false, detached.get("attached"));
                assertEquals("Widget detach must retain host core", true, detached.get("coreAlive"));
                long frames = number(detached, "submittedFrames");
                click("Attach");
                Map<String, Object> reattached = await(scenario, state -> number(state, "attaches") == count + 1
                        && number(state, "submittedFrames") > frames + 2);
                assertEquals(0L, number(reattached, "runtimeFailures"));
                android.util.Log.i("FoundationTextureTest", "cycle=" + cycle + " " + reattached);
            }
            FlutterFoundationIntegrationTest.screenshot("foundation-texture-after-20.png");
        }
    }

    private static long number(Map<String, Object> state, String name) {
        return ((Number) state.get(name)).longValue();
    }
    private static Map<String, Object> snapshot(ActivityScenario<FlutterFoundationActivity> scenario) {
        AtomicReference<Map<String, Object>> result = new AtomicReference<>();
        scenario.onActivity(activity -> {
            try {
                for (Field field : FlutterFoundationActivity.class.getDeclaredFields()) {
                    if (field.getType() == FoundationTextureProbe.class) {
                        field.setAccessible(true);
                        FoundationTextureProbe probe = (FoundationTextureProbe) field.get(activity);
                        if (probe != null) {
                            Map<String, Object> state = probe.snapshot();
                            Field audioField = FoundationTextureProbe.class.getDeclaredField("audio");
                            audioField.setAccessible(true);
                            AudioThread audio = (AudioThread) audioField.get(probe);
                            long playback = -1;
                            int underruns = -1;
                            if (audio != null) {
                                Field trackField = AudioThread.class.getDeclaredField("track");
                                trackField.setAccessible(true);
                                android.media.AudioTrack track = (android.media.AudioTrack) trackField.get(audio);
                                if (track != null) {
                                    try {
                                        playback = Integer.toUnsignedLong(track.getPlaybackHeadPosition());
                                        underruns = track.getUnderrunCount();
                                    } catch (IllegalStateException releasedDuringSnapshot) { }
                                }
                            }
                            state.put("audioPlaybackFrames", playback);
                            state.put("audioUnderruns", underruns);
                            result.set(state);
                        }
                    }
                }
            } catch (Exception failure) { throw new AssertionError(failure); }
        });
        assertNotNull("Debug host must own its native texture probe", result.get());
        return result.get();
    }
    private static Map<String, Object> await(ActivityScenario<FlutterFoundationActivity> scenario,
                                             Predicate<Map<String, Object>> predicate) {
        long deadline = SystemClock.uptimeMillis() + 20000;
        Map<String, Object> state;
        do {
            state = snapshot(scenario);
            if (predicate.test(state)) return state;
            SystemClock.sleep(100);
        } while (SystemClock.uptimeMillis() < deadline);
        throw new AssertionError("Native texture assertion timed out: " + state);
    }
    private static AccessibilityNodeInfo awaitLabel(String label) {
        long deadline = SystemClock.uptimeMillis() + 20000;
        do {
            var root = InstrumentationRegistry.getInstrumentation().getUiAutomation().getRootInActiveWindow();
            var node = findLabel(root, label);
            if (node != null) return node;
            SystemClock.sleep(100);
        } while (SystemClock.uptimeMillis() < deadline);
        throw new AssertionError("Missing texture UI control: " + label);
    }
    private static AccessibilityNodeInfo findLabel(AccessibilityNodeInfo node, String label) {
        if (node == null) return null;
        if (label.contentEquals(String.valueOf(node.getContentDescription()))
                || label.contentEquals(String.valueOf(node.getText()))) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            var found = findLabel(node.getChild(i), label);
            if (found != null) return found;
        }
        return null;
    }
    private static void click(String label) { FlutterFoundationIntegrationTest.click(awaitLabel(label)); }
    private static Rect bounds(AccessibilityNodeInfo node) {
        Rect result = new Rect(); node.getBoundsInScreen(result); return result;
    }
    private static void inject(long down, int action, Rect[] targets, int[] ids) {
        MotionEvent.PointerProperties[] properties = new MotionEvent.PointerProperties[targets.length];
        MotionEvent.PointerCoords[] coords = new MotionEvent.PointerCoords[targets.length];
        for (int i = 0; i < targets.length; i++) {
            properties[i] = new MotionEvent.PointerProperties(); properties[i].id = ids[i];
            properties[i].toolType = MotionEvent.TOOL_TYPE_FINGER;
            coords[i] = new MotionEvent.PointerCoords();
            coords[i].x = targets[i].centerX(); coords[i].y = targets[i].centerY();
            coords[i].pressure = 1; coords[i].size = 1;
        }
        MotionEvent event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                targets.length, properties, coords, 0, 0, 1, 1, 0, 0,
                android.view.InputDevice.SOURCE_TOUCHSCREEN, 0);
        try { assertTrue(InstrumentationRegistry.getInstrumentation().getUiAutomation().injectInputEvent(event, true)); }
        finally { event.recycle(); }
    }
}
