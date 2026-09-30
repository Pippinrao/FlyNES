package com.flynes.emu;

import static org.junit.Assert.*;
import android.content.Intent;
import android.os.SystemClock;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.platform.app.InstrumentationRegistry;
import java.lang.ref.WeakReference;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/** Opt-in real 20 round trips, with verified ART collections only at 5 and 20. */
public final class G2ReleaseMemoryTest {
    @Test public void observeTwentyReleaseRoundTrips() throws Exception {
        var args=InstrumentationRegistry.getArguments();
        org.junit.Assume.assumeTrue("Explicit G2 memory invocation required","true".equals(args.getString("g2Memory")));
        FlyNesApplication app=ApplicationProvider.getApplicationContext();
        boolean flutter="flutter".equals(args.getString("g1Entry"));
        assertTrue("G1 residual-owner budget is the Flutter game/hall round trip",flutter);
        String route=flutter?"flutter":"native";
        boolean debuggable=(app.getApplicationInfo().flags&android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE)!=0;
        assertFalse("Actual target must be Release",debuggable);
        assertTrue("Controlled same-APK native baseline required",BuildConfig.CONTROLLED_NATIVE_BASELINE);
        assertFalse("Cold process engine required",G2PerformanceUi.enginePresent(app));
        String canonical=args.getString("g1CanonicalId","");
        var settingsRepository=com.flynes.emu.settings.SettingsAccess.repository(app);
        var originalSettings=settingsRepository.load();
        var navigation=G2PerformanceUi.select(app,canonical);
        JSONObject report=new JSONObject().put("result","incomplete").put("route",route)
                .put("pid",android.os.Process.myPid()).put("targetDebuggable",debuggable).put("engineBefore",false);
        JSONArray cycles=new JSONArray(),checkpoints=new JSONArray(),transitions=new JSONArray();
        var games=new java.util.ArrayList<WeakReference<MainActivity>>();
        try {
            assertTrue(settingsRepository.save(originalSettings.toBuilder().audioEnabled(true).autosaveEnabled(true).build()));
            Intent intent=new Intent(app,flutter?FlutterFoundationActivity.class:HomeActivity.class);
            if(!flutter)intent.putExtra(ProductRoutes.NATIVE_BASELINE,true);
            try(ActivityScenario<?> scenario=ActivityScenario.launch(intent)) {
                for(int cycle=1;cycle<=20;cycle++) {
                    games.add(roundTrip(flutter,cycle,transitions));
                    cycles.put(G2PerformanceUi.memory().put("cycle",cycle));
                    if(cycle==5||cycle==20){
                        JSONObject checkpoint=G2PerformanceUi.afterGc(cycle);
                        long oldRetained=games.subList(0,games.size()-1).stream().filter(ref->ref.get()!=null).count();
                        checkpoint.put("priorGameOwnersRetained",oldRetained)
                                .put("audioThreads",FlutterFoundationIntegrationTest.audioThreads());
                        checkpoints.put(checkpoint);
                        assertEquals("Prior game owners must be collectible",0,oldRetained);
                    }
                }
                report.put("completedCycles",20).put("result","PASS");
            }
        } catch(Throwable failure) {
            report.put("result","failed");
            throw failure;
        } finally {
            // The presentation handoff replaces the original hall. Close every
            // Activity created in this cold test process before restoring prefs.
            InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                var monitor=androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance();
                var owned=new java.util.HashSet<android.app.Activity>();
                for(var stage:androidx.test.runner.lifecycle.Stage.values())owned.addAll(monitor.getActivitiesInStage(stage));
                for(var activity:owned)if(!activity.isDestroyed())activity.finish();
            });
            InstrumentationRegistry.getInstrumentation().waitForIdleSync();
            boolean restored=settingsRepository.save(originalSettings);
            restored &= G2PerformanceUi.restore(app,navigation);
            boolean engineAfter=G2PerformanceUi.enginePresent(app);
            report.put("cycles",cycles).put("checkpoints",checkpoints).put("transitions",transitions).put("preferencesRestored",restored)
                    .put("engineAfter",engineAfter).put("dartHeap",new JSONObject()
                            .put("status",flutter?"unavailable":"not_initialized").put("reason","Release VM service disabled"));
            if(!restored||(!flutter&&engineAfter))report.put("result","failed_cleanup");
            java.nio.file.Files.write(new java.io.File(app.getExternalFilesDir(null),"g2-memory-"+route+"-"+android.os.Process.myPid()+".json").toPath(),
                    report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            assertTrue("Navigation restored",restored);
            if(!flutter)assertFalse("Native round trips never initialize Flutter",engineAfter);
        }
    }
    private static WeakReference<MainActivity> roundTrip(boolean flutter,int cycle,JSONArray transitions) throws Exception {
        android.app.Activity[] outgoing={null};
        InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
            var monitor=androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance();
            for(var activity:monitor.getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED))
                if(activity instanceof FlutterFoundationActivity)outgoing[0]=activity;
        });
        assertNotNull("Current hall owner required before launch",outgoing[0]);
        if(flutter)G2PerformanceUi.clickPrimary();
        else FlutterFoundationIntegrationTest.click(FlutterFoundationIntegrationTest.awaitNode("launch_selected",true));
        assertTrue(FlutterFoundationIntegrationTest.awaitActivity(MainActivity.class));
        MainActivity game=FlutterFoundationIntegrationTest.playingActivity();
        var clockField=MainActivity.class.getDeclaredField("historyClock");clockField.setAccessible(true);
        var clock=(com.flynes.emu.save.HistoryClock)clockField.get(game);
        long before=clock.playedMs(),deadline=SystemClock.elapsedRealtime()+10000;
        while(clock.playedMs()<=before&&SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(25);
        assertTrue("Real core must advance each cycle",clock.playedMs()>before);
        assertEquals("One audio owner in game",1,FlutterFoundationIntegrationTest.audioThreads());
        // RESUMED/core progress precedes completion of the system window animation.
        // A coordinate tap during that animation can be consumed outside this View.
        // Wait for the outgoing owner to leave the screen, not a fixed sleep/retry.
        JSONObject transition=new JSONObject().put("cycle",cycle).put("coreAdvancedElapsedMs",SystemClock.elapsedRealtime());
        transitions.put(transition);
        boolean[] settled={false};
        String[] stage={"unknown"};
        deadline=SystemClock.elapsedRealtime()+10000;
        while(!settled[0]&&SystemClock.elapsedRealtime()<deadline){
            InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                var state=androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                        .getLifecycleStageOf(outgoing[0]);
                stage[0]=state.name();
                settled[0]=(state==androidx.test.runner.lifecycle.Stage.STOPPED
                        ||state==androidx.test.runner.lifecycle.Stage.DESTROYED)
                        &&game.hasWindowFocus()&&game.findViewById(R.id.pause_button).isShown();
            });
            if(!settled[0])SystemClock.sleep(25);
        }
        transition.put("outgoingStage",stage[0]).put("inputReadyElapsedMs",SystemClock.elapsedRealtime())
                .put("inputReady",settled[0]);
        assertTrue("Outgoing hall must stop and current game own the focused window before touch",settled[0]);
        androidx.test.espresso.Espresso.onView(androidx.test.espresso.matcher.ViewMatchers.withId(R.id.pause_button))
                .perform(androidx.test.espresso.action.ViewActions.click());
        androidx.test.espresso.Espresso.onView(androidx.test.espresso.matcher.ViewMatchers.withId(R.id.pause_game_center))
                .perform(androidx.test.espresso.action.ViewActions.scrollTo(),androidx.test.espresso.action.ViewActions.click());
        assertTrue(FlutterFoundationIntegrationTest.awaitActivity(flutter?FlutterFoundationActivity.class:HomeActivity.class));
        deadline=SystemClock.elapsedRealtime()+10000;
        while((!game.isDestroyed()||FlutterFoundationIntegrationTest.audioThreads()!=0)&&SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(25);
        assertTrue("Game owner destroyed after return",game.isDestroyed());
        assertEquals("Audio thread released",0,FlutterFoundationIntegrationTest.audioThreads());
        var handler=MainActivity.class.getDeclaredField("statusHandler");handler.setAccessible(true);
        var timer=MainActivity.class.getDeclaredField("historyTimer");timer.setAccessible(true);
        assertFalse("Save timer released",((android.os.Handler)handler.get(game)).hasCallbacks((Runnable)timer.get(game)));
        return new WeakReference<>(game);
    }
}
