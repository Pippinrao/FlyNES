package com.flynes.emu;

import static org.junit.Assert.*;
import static androidx.test.espresso.Espresso.onView;
import static androidx.test.espresso.action.ViewActions.*;
import static androidx.test.espresso.matcher.ViewMatchers.*;
import static org.hamcrest.Matchers.*;
import android.graphics.Rect;
import android.os.SystemClock;
import android.view.accessibility.AccessibilityNodeInfo;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.platform.app.InstrumentationRegistry;
import com.flynes.emu.save.*;
import com.flynes.emu.cover.AndroidCoverRepository;
import java.io.File;
import java.nio.file.Files;
import java.util.*;
import org.json.*;
import org.junit.Test;

/** Actual Flutter selection -> native history actions -> returned Flutter projection. */
public final class G2HistoryReturnTest {
    @Test public void restoreAndRestartRefreshHallWithoutLosingNavigation() throws Exception {
        org.junit.Assume.assumeTrue("Explicit task simulator invocation","true".equals(InstrumentationRegistry.getArguments().getString("g2HistoryReturn")));
        FlyNesApplication app=ApplicationProvider.getApplicationContext();
        assertTrue(android.os.Build.FINGERPRINT.contains("generic")||android.os.Build.FINGERPRINT.contains("emu64"));
        app.catalogRuntime().nativeReady().get(30,java.util.concurrent.TimeUnit.SECONDS);
        var prefs=app.getSharedPreferences("game_center_ui",0);var originalNav=new HashMap<String,Object>(prefs.getAll());
        var originalSettings=ProductSettings.read(app.settingsRepository());
        File reportFile=new File(app.getExternalFilesDir(null),"g2-history-return.json");
        JSONObject report=new JSONObject().put("result","incomplete").put("pid",android.os.Process.myPid());
        String key=null,id=null;long originalHead=0,oldCoverModified=0;boolean originalHeadPinned=false;byte[] oldCover=null;File cover=null;
        boolean ownerWrite="true".equals(InstrumentationRegistry.getArguments().getString("g2CoverOwnerWrite"));
        report.put("coverEvidenceMode",ownerWrite?"actual-core-frame-owner-write-fixture":"natural-quality-sampler");
        try {
            assertTrue(app.settingsRepository().save(originalSettings.toBuilder().audioEnabled(true).autosaveEnabled(true).build()));
            assertTrue(prefs.edit().putString("category","BUILTIN").putBoolean("multiplayerOnly",false).commit());
            G2ProcessRetentionTest.launchNormally(app);
            action(G2ProcessRetentionTest.awaitNode(n->label(n).equals("Search")||label(n).equals("搜索")));
            var input=G2ProcessRetentionTest.awaitNode(AccessibilityNodeInfo::isEditable);
            var text=new android.os.Bundle();text.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,"nes");
            assertTrue(input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,text));
            InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                var monitor=androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance();
                var current=monitor.getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED).iterator().next();
                ((android.view.inputmethod.InputMethodManager)app.getSystemService(android.content.Context.INPUT_METHOD_SERVICE))
                        .hideSoftInputFromWindow(current.getWindow().getDecorView().getWindowToken(),0);
            });
            await(()->cards().size()>=2,"Filtered builtin cards");
            var grid=grid();String beforeScroll=cards().get(0).label;
            assertTrue("Exercise real nonzero catalog scroll",grid.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD));
            await(()->!cards().isEmpty()&&!cards().get(0).label.equals(beforeScroll),"Catalog scroll changed visible anchor");
            InstrumentationRegistry.getInstrumentation().getUiAutomation().waitForIdle(200,5000);
            var visible=cards();var selected=visible.get(visible.size()-1);
            action(G2ProcessRetentionTest.awaitNode(n->n.isClickable()&&label(n).equals(selected.label)));
            InstrumentationRegistry.getInstrumentation().getUiAutomation().waitForIdle(200,5000);
            G2ProcessRetentionTest.awaitNode(G2PerformanceUi::primary);
            id=prefs.getString("selected","");assertFalse(id.isEmpty());
            var selectedRow=app.catalogRuntime().gameCenterSnapshot().rows().stream().filter(r->r.canonicalId().equals(prefs.getString("selected",""))).findFirst().orElseThrow();
            assertTrue(selectedRow.builtin());
            String title=selected.label;Rect anchor=selectedBounds(title);
            var navigation=new HashMap<String,Object>(prefs.getAll());
            cover=new AndroidCoverRepository(app).fileForTest(id);if(cover.isFile()){oldCover=Files.readAllBytes(cover.toPath());oldCoverModified=cover.lastModified();}
            screenshot(app,"g2-history-before.png");
            report.put("canonicalId",id).put("query","nes").put("anchorBefore",anchor.flattenToString()).put("coverBeforeSha256",oldCover==null?"":G2ProcessRetentionTest.digest(oldCover));
            MainActivity game=launchGame();
            assertEquals(id,field(game,"currentCoverGameId"));
            key=((com.flynes.emu.data.RomIdentity)field(game,"currentRomIdentity")).sha1();
            var store=(HistoryStore)field(game,"historyStore");originalHead=store.head(key);
            if(originalHead!=0){long prior=originalHead;originalHeadPinned=Arrays.stream(store.list(key)).filter(e->e.id()==prior).findFirst().orElseThrow().pinned();store.pin(originalHead,true);}
            var clock=(HistoryClock)field(game,"historyClock");long began=clock.playedMs();
            touchControl(game,clock,com.flynes.emu.input.GamepadHitMap.Control.START);
            for(int choice=0;choice<3;choice++){long menu=clock.playedMs();await(()->clock.playedMs()>=menu+350,"Real menu progression before next input");touchControl(game,clock,com.flynes.emu.input.GamepadHitMap.Control.A);}
            await(()->clock.playedMs()>=began+6500,"Real frames and sampled cover before checkpoint A");
            pause(game);String labelA="G2 return A "+System.nanoTime();manualSave(labelA);
            long checkpoint=store.head(key);byte[] stateA=store.read(key,checkpoint,false);byte[] thumbnailA=store.read(key,checkpoint,true);
            assertTrue(thumbnailA.length>0);var capturedA=actualFrame(game,id);long playedA=clock.playedMs();
            onView(withId(R.id.pause_continue)).perform(scrollTo(),click());
            await(()->clock.playedMs()>=playedA+1500,"Real progress after checkpoint A");pause(game);
            String labelB="G2 return B "+System.nanoTime();manualSave(labelB);long newer=store.head(key);
            assertNotEquals(checkpoint,newer);assertFalse(Arrays.equals(stateA,store.read(key,newer,false)));
            onView(withId(R.id.pause_history)).perform(scrollTo(),click());
            onView(allOf(isAssignableFrom(android.widget.Button.class),withText(containsString(labelA)))).perform(scrollTo(),click());
            onView(withId(android.R.id.button1)).perform(click());
            assertEquals("Real history restore selected A",checkpoint,store.head(key));
            assertArrayEquals(stateA,((NesCore)field(game,"core")).saveState());
            if(ownerWrite)new AndroidCoverRepository(app).store(capturedA);
            screenshot(app,"g2-history-restored-native.png");
            onView(withId(R.id.pause_game_center)).perform(scrollTo(),click());
            awaitHall(game);assertNavigation(app,navigation,title,anchor);
            try(var read=new HistoryStore(new File(app.getFilesDir(),"save-history.sqlite"))){assertEquals(checkpoint,read.head(key));assertArrayEquals(thumbnailA,read.read(key,checkpoint,true));}
            var restored=G2ProcessRetentionTest.invoke(app,"catalogItem",Map.of("canonicalId",id));
            assertEquals("available",G2ProcessRetentionTest.invoke(app,"resumeCapability",Map.of("canonicalId",id)).get("state"));
            assertTrue("Real captured cover exists",cover.isFile());
            report.put("restoredHead",checkpoint).put("newerBeforeRestore",newer).put("restoreCoverRevision",restored.get("coverRevision"))
                    .put("restoreCoverSha256",G2ProcessRetentionTest.digest(Files.readAllBytes(cover.toPath())));
            exportCover(app,cover,"g2-history-restored-cover.png");
            assertNotEquals("U24 requires visibly different actual native cover pixels",report.getString("coverBeforeSha256"),report.getString("restoreCoverSha256"));
            screenshot(app,"g2-history-restored-hall.png");
            game=launchGame();pause(game);
            store=(HistoryStore)field(game,"historyStore");
            onView(withId(R.id.pause_restart)).perform(scrollTo(),click());onView(withId(android.R.id.button1)).perform(click());
            long fresh=store.head(key);assertNotEquals(checkpoint,fresh);
            var entry=Arrays.stream(store.list(key)).filter(e->e.id()==fresh).findFirst().orElseThrow();
            assertEquals(0,entry.playedMs());assertEquals(0,entry.parent());assertArrayEquals(stateA,store.read(key,checkpoint,false));
            screenshot(app,"g2-history-restarted-native.png");
            onView(withId(R.id.pause_game_center)).perform(scrollTo(),click());awaitHall(game);assertNavigation(app,navigation,title,anchor);
            try(var read=new HistoryStore(new File(app.getFilesDir(),"save-history.sqlite"))){assertEquals(fresh,read.head(key));}
            var restarted=G2ProcessRetentionTest.invoke(app,"catalogItem",Map.of("canonicalId",id));
            assertEquals("available",G2ProcessRetentionTest.invoke(app,"resumeCapability",Map.of("canonicalId",id)).get("state"));
            report.put("restartHead",fresh).put("restartCoverRevision",restarted.get("coverRevision"))
                    .put("restartCoverSha256",G2ProcessRetentionTest.digest(Files.readAllBytes(cover.toPath()))).put("result","PASS");
            exportCover(app,cover,"g2-history-restarted-cover.png");screenshot(app,"g2-history-restarted-hall.png");
        } catch(Throwable failure) {
            report.put("failure",failure.toString());screenshot(app,"g2-history-failure.png");throw failure;
        } finally {
            final String restoreKey=key;final long restoreHead=originalHead,restoreModified=oldCoverModified;
            final boolean restorePinned=originalHeadPinned;final File restoreCover=cover;final byte[] restorePixels=oldCover;
            final boolean[] restored={false,false,false,false};
            Throwable cleanup=G2FixtureCleanup.all(G2ProcessRetentionTest::finishHosts,
                ()->{if(restoreKey!=null)try(var store=new HistoryStore(new File(app.getFilesDir(),"save-history.sqlite"))){store.setHead(restoreKey,restoreHead);if(restoreHead!=0)store.pin(restoreHead,restorePinned);}restored[0]=true;},
                ()->{if(restoreCover!=null&&restorePixels!=null){Files.write(restoreCover.toPath(),restorePixels);assertTrue("Restore original cover revision",restoreCover.setLastModified(restoreModified));}
                    else if(restoreCover!=null&&restoreCover.exists())assertTrue("Remove only the task-created cover",restoreCover.delete());restored[1]=true;},
                ()->{assertTrue("Settings restored",app.settingsRepository().save(originalSettings));restored[2]=true;},
                ()->{assertTrue("Navigation restored",G2PerformanceUi.restore(app,originalNav));restored[3]=true;});
            report.put("preferencesRestored",restored[2]&&restored[3]).put("originalHeadRestored",restored[0]).put("originalHead",originalHead)
                    .put("coverRestored",restored[1]).put("originalCoverModified",oldCoverModified);
            if(cleanup!=null)report.put("result","failed_cleanup").put("cleanupFailure",cleanup.toString());
            Files.write(reportFile.toPath(),report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            if(cleanup!=null)throw new AssertionError("Fixture cleanup failed",cleanup);
        }
    }
    private static com.flynes.emu.cover.CoverFrame actualFrame(MainActivity game,String id)throws Exception {
        NesCore core=(NesCore)field(game,"core");var pixels=java.nio.ByteBuffer.allocateDirect(4*1024*1024);int[] info=new int[5];
        var copied=core.copyVideoFrameIfNew(pixels,info,-1);assertEquals(com.flynes.emu.video.FrameCopyResult.Kind.NEW,copied.kind());
        try(var frame=com.flynes.emu.video.PublishedFrame.fromNative(copied.sequence(),info,pixels)){
            return com.flynes.emu.cover.CoverFrame.copyOf(id,frame);
        }
    }
    private static void exportCover(FlyNesApplication app,File cover,String name)throws Exception {
        File output=new File(app.getExternalFilesDir(null),name);
        try(var stream=new java.io.FileOutputStream(output)){stream.write(Files.readAllBytes(cover.toPath()));}
        assertTrue(output.setReadable(true,false));
    }
    private static void touchControl(MainActivity game,HistoryClock clock,com.flynes.emu.input.GamepadHitMap.Control control){
        float[] point=new float[2];InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
            GamepadView pad=game.findViewById(R.id.gamepad);var target=pad.hitMapForTest().target(control);
            int[] origin=new int[2];pad.getLocationOnScreen(origin);point[0]=origin[0]+target.centerX();point[1]=origin[1]+target.centerY();
        });
        long down=SystemClock.uptimeMillis(),before=clock.playedMs();
        for(int action:new int[]{android.view.MotionEvent.ACTION_DOWN,android.view.MotionEvent.ACTION_UP}){
            var event=android.view.MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,point[0],point[1],0);
            event.setSource(android.view.InputDevice.SOURCE_TOUCHSCREEN);InstrumentationRegistry.getInstrumentation().sendPointerSync(event);event.recycle();
            if(action==android.view.MotionEvent.ACTION_DOWN)await(()->clock.playedMs()>=before+100,"Actual core advances during "+control+" touch");
        }
    }
    private record Card(String label,Rect bounds){}
    private static List<Card> cards(){
        var node=grid();var result=new ArrayList<Card>();Rect region=new Rect();node.getBoundsInScreen(region);collect(node,region,result);return result;
    }
    private static void collect(AccessibilityNodeInfo node,Rect region,List<Card> out){
        Rect bounds=new Rect();node.getBoundsInScreen(bounds);
        if(node.isClickable()&&!label(node).equals("null")&&!label(node).isEmpty()&&G2PerformanceUi.visible(node)&&region.contains(bounds))out.add(new Card(label(node),bounds));
        for(int i=0;i<node.getChildCount();i++){var child=node.getChild(i);if(child!=null)collect(child,region,out);}
    }
    private static AccessibilityNodeInfo grid(){
        var filter=G2ProcessRetentionTest.awaitNode(n->label(n).equals("Two-player")||label(n).equals("双人支持"));Rect anchor=new Rect();filter.getBoundsInScreen(anchor);
        return G2ProcessRetentionTest.awaitNode(n->{Rect r=new Rect();n.getBoundsInScreen(r);return "android.widget.HorizontalScrollView".contentEquals(n.getClassName())&&r.top>=anchor.bottom&&r.left<anchor.right&&r.right>anchor.left;});
    }
    private static Rect selectedBounds(String title){return cards().stream().filter(c->c.label.equals(title)).findFirst().orElseThrow().bounds;}
    private static String label(AccessibilityNodeInfo node){return G2ProcessRetentionTest.label(node);}
    private static void action(AccessibilityNodeInfo node){assertTrue(node.performAction(AccessibilityNodeInfo.ACTION_CLICK));}
    private static MainActivity launchGame()throws Exception{
        android.app.Activity[] outgoing={null};
        InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
            var monitor=androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance();
            for(var activity:monitor.getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED))if(activity instanceof FlutterFoundationActivity)outgoing[0]=activity;
        });assertNotNull(outgoing[0]);G2PerformanceUi.clickPrimary();
        assertTrue(FlutterFoundationIntegrationTest.awaitActivity(MainActivity.class));MainActivity game=FlutterFoundationIntegrationTest.playingActivity();
        await(()->{boolean[] ready={false};InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
            var state=androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance().getLifecycleStageOf(outgoing[0]);
            ready[0]=(state==androidx.test.runner.lifecycle.Stage.STOPPED||state==androidx.test.runner.lifecycle.Stage.DESTROYED)&&game.hasWindowFocus()&&game.findViewById(R.id.pause_button).isShown();
        });return ready[0];},"Outgoing hall stopped and game window owns input");return game;
    }
    private static void pause(MainActivity game){onView(withId(R.id.pause_button)).perform(click());onView(withId(R.id.pause_continue)).check(androidx.test.espresso.assertion.ViewAssertions.matches(isDisplayed()));}
    private static void manualSave(String label){onView(withId(R.id.pause_save)).perform(scrollTo(),click());onView(isAssignableFrom(android.widget.EditText.class)).perform(replaceText(label));onView(withId(android.R.id.button1)).perform(click());}
    private static void awaitHall(MainActivity game){G2ProcessRetentionTest.awaitNode(G2PerformanceUi::primary);await(()->game.isDestroyed()&&FlutterFoundationIntegrationTest.audioThreads()==0,"Game owner fully released");}
    private static void assertNavigation(FlyNesApplication app,Map<String,Object> before,String title,Rect anchor){
        var after=app.getSharedPreferences("game_center_ui",0).getAll();for(String k:List.of("category","selected","multiplayerOnly","product.selected.builtin"))assertEquals(k,before.get(k),after.get(k));
        assertEquals("Query retained", "nes",String.valueOf(G2ProcessRetentionTest.awaitNode(AccessibilityNodeInfo::isEditable).getText()));
        assertEquals("Selected card scroll position retained",anchor,selectedBounds(title));
        G2ProcessRetentionTest.awaitNode(n->G2PerformanceUi.primary(n)&&(label(n).equals("Continue")||label(n).equals("继续")));
    }
    private static Object field(Object value,String name)throws Exception{var f=value.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(value);}
    private static void await(java.util.function.BooleanSupplier predicate,String reason){long end=SystemClock.elapsedRealtime()+15000;while(!predicate.getAsBoolean()&&SystemClock.elapsedRealtime()<end)SystemClock.sleep(25);assertTrue(reason,predicate.getAsBoolean());}
    private static void screenshot(FlyNesApplication app,String name){FlutterFoundationIntegrationTest.screenshot(name);}
}
