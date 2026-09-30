package com.flynes.emu;

import static org.junit.Assert.*;
import android.content.Intent;
import android.os.SystemClock;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Read-only bridge assertions plus real game/settings owner round trip; no fixtures clear app data. */
@RunWith(AndroidJUnit4.class)
public class ProductBridgeIntegrationTest {
    @Test public void bootstrapFailureShowsRasterizedRetryAndTransientAckRecovers() throws Exception {
        try(var hall=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            var bridge=app().productBridge();var engine=app().foundationEngine();
            var failBootstrap=new java.util.concurrent.atomic.AtomicBoolean(true);
            var ackAttempts=new java.util.concurrent.atomic.AtomicInteger();
            MethodChannel interception=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"flynes/product.v1");
            InstrumentationRegistry.getInstrumentation().runOnMainSync(()->interception.setMethodCallHandler((call,result)->{
                if(call.method.equals("bootstrap")&&failBootstrap.getAndSet(false)){result.error("native_unavailable","native_unavailable",null);return;}
                if(call.method.equals("presentationReady")&&ackAttempts.incrementAndGet()==1){result.error("native_unavailable","native_unavailable",null);return;}
                bridge.onMethodCall(call,result);
            }));
            try(var failed=ActivityScenario.<FlutterFoundationActivity>launch(new Intent(app(),FlutterFoundationActivity.class).putExtra(ProductBridge.ROUTE_EXTRA,"settings"))) {
                android.view.accessibility.AccessibilityNodeInfo retry=awaitText("重试","Retry");
                assertTrue("Transient acknowledgement is retried",ackAttempts.get()>=2);
                failed.onActivity(activity->{
                    try {var field=FlutterFoundationActivity.class.getDeclaredField("presentation");field.setAccessible(true);
                        assertTrue("The error surface has passed the real native gate",((ProductPresentationGate)field.get(activity)).ready());
                    }catch(ReflectiveOperationException error){throw new AssertionError(error);}
                });
                var bitmap=InstrumentationRegistry.getInstrumentation().getUiAutomation().takeScreenshot();
                try(var output=new java.io.FileOutputStream(new java.io.File(app().getFilesDir(),"presentation-error-fixture.png"))){bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,output);}finally{bitmap.recycle();}
                assertTrue(retry.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK));
                awaitText("画质预设","Quality preset");assertSame(engine,app().foundationEngine());
            }finally {InstrumentationRegistry.getInstrumentation().runOnMainSync(()->interception.setMethodCallHandler(bridge));}
        }
    }
    @Test public void abandonedHallHandoffDropsReferenceAndResumesOriginalGame() throws Exception {
        try(var hall=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            var bridge=app().productBridge();var boot=invoke(bridge,"bootstrap",0,Map.of());
            long generation=((Number)boot.get("hostGeneration")).longValue();
            app().catalogRuntime().nativeReady().get(30,TimeUnit.SECONDS);
            String id=app().catalogRuntime().gameCenterSnapshot().rows().stream().filter(r->r.builtin()&&r.launchable()).findFirst().orElseThrow().canonicalId();
            CompletableFuture.runAsync(()->{try{invoke(bridge,"launch",generation,Map.of("canonicalId",id,"purpose","single"));}catch(Exception ignored){}});
            MainActivity game=awaitActivity(MainActivity.class);var engine=app().foundationEngine();
            var delayed=new AtomicReference<Runnable>();CountDownLatch recreatedReady=new CountDownLatch(1);
            MethodChannel interception=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"flynes/product.v1");
            InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                try{var navigate=MainActivity.class.getDeclaredMethod("closePauseForNavigation",Class.class);navigate.setAccessible(true);navigate.invoke(game,SettingsActivity.class);}
                catch(Exception error){throw new AssertionError(error);}
            });
            var destination=awaitActivity(FlutterFoundationActivity.class);awaitText("画质预设","Quality preset");
            InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                // Seed an in-flight borrowed handoff on a drawn host to isolate recreation cleanup.
                destination.getIntent().putExtra("native_game_handoff",app().prepareHallHandoff(game).getStringExtra("native_game_handoff"));
                interception.setMethodCallHandler((call,result)->{
                    if(call.method.equals("presentationReady")){delayed.set(()->bridge.onMethodCall(call,result));recreatedReady.countDown();}
                    else bridge.onMethodCall(call,result);
                });
                destination.recreate();
            });
            try {
                FlutterFoundationActivity replacement;long deadline=SystemClock.elapsedRealtime()+10000;
                do{SystemClock.sleep(20);replacement=awaitActivity(FlutterFoundationActivity.class);}while(replacement==destination&&SystemClock.elapsedRealtime()<deadline);
                assertNotSame("The drawn host must recreate",destination,replacement);
                assertTrue(recreatedReady.await(10,TimeUnit.SECONDS));
                var field=FlyNesApplication.class.getDeclaredField("gameHandoff");field.setAccessible(true);
                final var current=replacement;
                AtomicReference<Object> pendingGame=new AtomicReference<>();
                InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                    try{pendingGame.set(((ProductGameHandoff<?>)field.get(app())).pending());}
                    catch(Exception error){throw new AssertionError(error);}
                });
                assertSame("Recreation must retain the outgoing game until the new token is acknowledged",game,pendingGame.get());
                InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                    assertFalse(current.presentationReady(destination.presentationToken(),99999));
                    try{var gate=FlutterFoundationActivity.class.getDeclaredField("presentation");gate.setAccessible(true);
                        assertFalse("Old ack must not reveal the recreated host",((ProductPresentationGate)gate.get(current)).ready());}
                    catch(Exception error){throw new AssertionError(error);}
                    current.finish();
                });
                assertSame(game,awaitActivity(MainActivity.class));assertFalse(game.isFinishing());
                deadline=SystemClock.elapsedRealtime()+10000;
                while(!current.isDestroyed()&&SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(20);
                assertTrue("Abandoned destination must finish destruction",current.isDestroyed());
                InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                    try{pendingGame.set(((ProductGameHandoff<?>)field.get(app())).pending());}catch(Exception error){throw new AssertionError(error);}
                    delayed.getAndSet(null).run();
                });
                assertNull("Destruction must release the borrowed outgoing game",pendingGame.get());
                assertFalse(game.isFinishing());assertSame(engine,app().foundationEngine());
            }finally {InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                interception.setMethodCallHandler(bridge);
                Runnable reply=delayed.getAndSet(null);if(reply!=null)reply.run();
                for(var activity:androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED))
                    if(activity instanceof FlutterFoundationActivity)activity.finish();
                game.finish();
            });}
        }
    }
    private android.view.accessibility.AccessibilityNodeInfo awaitText(String... choices) throws Exception {
        long deadline=SystemClock.elapsedRealtime()+10000;
        do {
            var found=findText(InstrumentationRegistry.getInstrumentation().getUiAutomation().getRootInActiveWindow(),choices);
            if(found!=null)return found;SystemClock.sleep(50);
        }while(SystemClock.elapsedRealtime()<deadline);
        throw new AssertionError("Expected visible text: "+Arrays.toString(choices));
    }
    private android.view.accessibility.AccessibilityNodeInfo findText(android.view.accessibility.AccessibilityNodeInfo node,String[] choices) {
        if(node==null)return null;
        for(String text:choices)if(String.valueOf(node.getText()).contains(text)||String.valueOf(node.getContentDescription()).contains(text))return node;
        for(int i=0;i<node.getChildCount();i++){var found=findText(node.getChild(i),choices);if(found!=null)return found;}
        return null;
    }
    @Test public void hallHandoffKeepsOutgoingGameUntilDestinationAndRetiresOldHall() throws Exception {
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            AtomicReference<FlutterFoundationActivity> oldHall=new AtomicReference<>();scenario.onActivity(oldHall::set);
            var bridge=app().productBridge();var boot=invoke(bridge,"bootstrap",0,Map.of());
            long generation=((Number)boot.get("hostGeneration")).longValue();
            app().catalogRuntime().nativeReady().get(30,TimeUnit.SECONDS);
            String id=app().catalogRuntime().gameCenterSnapshot().rows().stream().filter(r->r.builtin()&&r.launchable()).findFirst().orElseThrow().canonicalId();
            var engine=app().foundationEngine();
            CompletableFuture.runAsync(()->{try{invoke(bridge,"launch",generation,Map.of("canonicalId",id,"purpose","single"));}catch(Exception ignored){}});
            MainActivity game=awaitActivity(MainActivity.class);
            var navigate=MainActivity.class.getDeclaredMethod("closePauseForNavigation",Class.class);navigate.setAccessible(true);
            InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                try{navigate.invoke(game,HomeActivity.class);}catch(Exception error){throw new AssertionError(error);}
                assertFalse("The outgoing valid window must remain until presentation",game.isFinishing());
            });
            FlutterFoundationActivity destination=awaitActivity(FlutterFoundationActivity.class);
            long deadline=SystemClock.elapsedRealtime()+10000;
            while(!game.isFinishing()&&SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(20);
            assertTrue("Matching raster must complete the handoff",game.isFinishing());
            assertNotSame(oldHall.get(),destination);assertTrue(oldHall.get().isFinishing());
            assertSame(engine,app().foundationEngine());assertFalse(destination.isFinishing());
            var restored=invoke(bridge,"bootstrap",0,Map.of());
            assertEquals("hall",((Map<?,?>)restored.get("context")).get("route"));
            var stale=invoke(bridge,"presentationReady",((Number)restored.get("hostGeneration")).longValue(),Map.of("token",oldHall.get().presentationToken(),"frameNumber",99999));
            assertEquals(false,stale.get("accepted"));
        }
    }
    @Test public void flutterOnlyLanguageChangeAppliesToNextNativePage() throws Exception {
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            var bridge=app().productBridge();
            var bootstrap=invoke(bridge,"bootstrap",0,Map.of());
            long host=((Number)bootstrap.get("hostGeneration")).longValue();
            String previous=ProductSettings.read(app().settingsRepository()).localeTag();
            try {
                invoke(bridge,"patchSetting",host,Map.of("key","localeTag","value","zh-Hans"));
                InstrumentationRegistry.getInstrumentation().waitForIdleSync();
                if(android.os.Build.VERSION.SDK_INT>=33) {
                    var locales=app().getSystemService(android.app.LocaleManager.class).getApplicationLocales();
                    assertFalse("Flutter-only host must update Android per-app locale",locales.isEmpty());
                    assertEquals("zh",locales.get(0).getLanguage());
                }
                try(var nativePage=ActivityScenario.launch(ControlLayoutActivity.class)) {
                    nativePage.onActivity(activity->assertEquals("操控布局",activity.getString(R.string.control_layout_title)));
                }
            } finally {
                var fresh=invoke(bridge,"bootstrap",0,Map.of());
                invoke(bridge,"patchSetting",((Number)fresh.get("hostGeneration")).longValue(),Map.of("key","localeTag","value",previous));
            }
        }
    }

    @Test public void nearbySelectRunsOffMainAndHostInvalidationDoesNotWaitForDecode() throws Exception {
        NearbyMvpOwner room=new NearbyMvpOwner();
        var sessionField=NearbyMvpOwner.class.getDeclaredField("session");sessionField.setAccessible(true);
        sessionField.set(room,new NearbyMvpSession());
        CountDownLatch selected=new CountDownLatch(1),release=new CountDownLatch(1);
        var selectOnMain=new java.util.concurrent.atomic.AtomicBoolean();
        var laterEffects=new java.util.concurrent.atomic.AtomicInteger();
        AtomicReference<ProductBridge> adapter=new AtomicReference<>();
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            scenario.onActivity(activity->{
                var bridge=new ProductBridge(app(),new MethodChannel(app().foundationEngine().getDartExecutor().getBinaryMessenger(),
                        "flynes/product-nearby-worker-test"),room,(id,original,complete)->new ProductNearbySelection.Port(){
                    public void ready(){}
                    public ProductNearbySelection.Selection load(){return new ProductNearbySelection.Selection(new byte[]{1},"candidate","candidate");}
                    public int state(){return NearbyMvpSession.LOBBY;}
                    public boolean returnLobby(){return true;}
                    public boolean select(ProductNearbySelection.Selection value){
                        selectOnMain.set(android.os.Looper.myLooper()==android.os.Looper.getMainLooper());selected.countDown();
                        // Let the RED assertion report the thread violation without hanging Android's main looper.
                        if(selectOnMain.get())return false;
                        try{return release.await(10,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();return false;}
                    }
                    public boolean confirm(){laterEffects.incrementAndGet();return true;}
                    public void publish(ProductNearbySelection.Selection value){laterEffects.incrementAndGet();}
                    public void complete(){laterEffects.incrementAndGet();complete.run();}
                });bridge.attach(activity);adapter.set(bridge);
            });
            var bridge=adapter.get();long host=((Number)invoke(bridge,"bootstrap",0,Map.of()).get("hostGeneration")).longValue();
            var result=CompletableFuture.supplyAsync(()->{try{return invoke(bridge,"launch",host,Map.of("canonicalId","fixture","purpose","nearby"));}catch(Exception e){throw new CompletionException(e);}});
            assertTrue(selected.await(3,TimeUnit.SECONDS));
            assertFalse("Port.select must execute on the product worker, never the Android main thread",selectOnMain.get());
            CountDownLatch transitioned=new CountDownLatch(1);
            new android.os.Handler(android.os.Looper.getMainLooper()).post(()->{
                scenario.onActivity(activity->{bridge.detach(activity);bridge.attach(activity);});transitioned.countDown();
            });
            assertTrue("Host transition must remain responsive while native selection is blocked",transitioned.await(2,TimeUnit.SECONDS));
            release.countDown();
            Throwable failure=assertThrows(ExecutionException.class,()->result.get(5,TimeUnit.SECONDS));
            while(failure.getCause()!=null)failure=failure.getCause();assertEquals("stale_host",failure.getMessage());
            assertEquals("Invalidation suppresses confirmation, metadata and completion",0,laterEffects.get());
            scenario.onActivity(activity->{assertFalse(activity.isFinishing());bridge.detach(activity);});
        }finally {release.countDown();room.close();}
    }
    @Test public void nearbyHostReplacementDuringReadinessDoesNotMutateOrFinishNewHost() throws Exception {
        assertNearbyReplacementSafe(false);
    }
    @Test public void nearbyRoomReplacementDuringContentLoadDoesNotSelectIntoNewRoom() throws Exception {
        assertNearbyReplacementSafe(true);
    }
    private void assertNearbyReplacementSafe(boolean replaceRoom) throws Exception {
        NearbyMvpOwner room=new NearbyMvpOwner();
        java.lang.reflect.Field sessionField=NearbyMvpOwner.class.getDeclaredField("session");sessionField.setAccessible(true);
        sessionField.set(room,new NearbyMvpSession());room.gameTitle("original");room.gameKey("original");
        var releases=new java.util.concurrent.atomic.AtomicInteger();room.attachNetworkLease(releases::incrementAndGet);
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        var selects=new java.util.concurrent.atomic.AtomicInteger();var confirms=new java.util.concurrent.atomic.AtomicInteger();
        var publishes=new java.util.concurrent.atomic.AtomicInteger();var completes=new java.util.concurrent.atomic.AtomicInteger();
        AtomicReference<ProductBridge> adapter=new AtomicReference<>();
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            scenario.onActivity(activity->{
                var bridge=new ProductBridge(app(),new MethodChannel(app().foundationEngine().getDartExecutor().getBinaryMessenger(),
                        "flynes/product-nearby-lease-"+replaceRoom),room,(id,original,complete)->new ProductNearbySelection.Port(){
                    private void waitAtBoundary() throws Exception {entered.countDown();if(!release.await(10,TimeUnit.SECONDS))throw new java.io.IOException("fixture timeout");}
                    public void ready() throws Exception {if(!replaceRoom)waitAtBoundary();}
                    public ProductNearbySelection.Selection load() throws Exception {if(replaceRoom)waitAtBoundary();return new ProductNearbySelection.Selection(new byte[]{1},"candidate","candidate");}
                    public int state(){return NearbyMvpSession.LOBBY;}
                    public boolean returnLobby(){throw new AssertionError("Fixture already in lobby");}
                    public boolean select(ProductNearbySelection.Selection selection){selects.incrementAndGet();return true;}
                    public boolean confirm(){confirms.incrementAndGet();return true;}
                    public void publish(ProductNearbySelection.Selection selection){publishes.incrementAndGet();room.gameTitle(selection.title());room.gameKey(selection.key());}
                    public void complete(){completes.incrementAndGet();complete.run();}
                });bridge.attach(activity);adapter.set(bridge);
            });
            var bridge=adapter.get();long host=((Number)invoke(bridge,"bootstrap",0,Map.of()).get("hostGeneration")).longValue();
            CompletableFuture<Map<?,?>> result=CompletableFuture.supplyAsync(()->{try{return invoke(bridge,"launch",host,Map.of("canonicalId","fixture","purpose","nearby"));}catch(Exception e){throw new CompletionException(e);}});
            assertTrue(entered.await(3,TimeUnit.SECONDS));
            if(replaceRoom) {
                synchronized(room){room.resetSessionKeepingNetwork();sessionField.set(room,new NearbyMvpSession());room.gameTitle("replacement");room.gameKey("replacement");}
            } else scenario.onActivity(activity->{bridge.detach(activity);bridge.attach(activity);});
            NearbyMvpSession retained=room.session();release.countDown();
            Throwable failure=org.junit.Assert.assertThrows(ExecutionException.class,()->result.get(5,TimeUnit.SECONDS));
            while(failure.getCause()!=null)failure=failure.getCause();
            assertEquals(replaceRoom?"nearby_unavailable":"stale_host",failure.getMessage());
            assertEquals(0,selects.get());assertEquals(0,confirms.get());assertEquals(0,publishes.get());assertEquals(0,completes.get());
            assertSame(retained,room.session());assertEquals(replaceRoom?"replacement":"original",room.gameTitle());assertEquals(0,releases.get());
            scenario.onActivity(activity->{assertFalse("A stale chooser must not finish the current host",activity.isFinishing());bridge.detach(activity);});
        }finally {release.countDown();room.close();}
        assertEquals(1,releases.get());
    }
    @Test public void scanProgressInvalidatesSourcesWithoutQueuingCatalogRefreshes() throws Exception {
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            List<List<?>> domains=new CopyOnWriteArrayList<>();AtomicReference<ProductBridge> adapter=new AtomicReference<>();
            scenario.onActivity(activity->{
                var channel=new MethodChannel(app().foundationEngine().getDartExecutor().getBinaryMessenger(),"flynes/product-progress-test") {
                    @Override public void invokeMethod(String method,Object arguments){
                        if(method.equals("projectionChanged"))domains.add((List<?>)((Map<?,?>)arguments).get("domains"));
                    }
                };
                var bridge=new ProductBridge(app(),channel);bridge.attach(activity);adapter.set(bridge);
            });
            var bridge=adapter.get();long host=((Number)invoke(bridge,"bootstrap",0,Map.of()).get("hostGeneration")).longValue();
            InstrumentationRegistry.getInstrumentation().waitForIdleSync();domains.clear();
            var op=app().catalogRuntime().scanOperations().begin("observation-fixture-"+UUID.randomUUID());
            try {
                op.enumerating();op.ingesting(2);op.advanced();
                InstrumentationRegistry.getInstrumentation().waitForIdleSync();
                assertFalse(domains.isEmpty());
                for(var changed:domains)assertEquals("Uncommitted progress must not enqueue catalog queries",List.of("sources"),changed);
            } finally {op.finish("cancelled","");invoke(bridge,"detach",host,Map.of());}
        }
    }
    @Test public void explicitDetachAndHiddenHostStopEventsWithoutStoppingOwner() throws Exception {
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            List<String> events=new CopyOnWriteArrayList<>();AtomicReference<ProductBridge> adapter=new AtomicReference<>();
            scenario.onActivity(activity->{
                MethodChannel channel=new MethodChannel(app().foundationEngine().getDartExecutor().getBinaryMessenger(),"flynes/product-lease-test") {
                    @Override public void invokeMethod(String method,Object arguments){events.add(method);}
                };
                var bridge=new ProductBridge(app(),channel);bridge.attach(activity);adapter.set(bridge);
            });
            var bridge=adapter.get();long host=((Number)invoke(bridge,"bootstrap",0,Map.of()).get("hostGeneration")).longValue();
            events.clear();invoke(bridge,"detach",host,Map.of());
            scenario.onActivity(bridge::returned);InstrumentationRegistry.getInstrumentation().waitForIdleSync();
            assertTrue("Detached subscription must receive no projections",events.isEmpty());
            invoke(bridge,"bootstrap",0,Map.of());scenario.onActivity(bridge::returned);
            InstrumentationRegistry.getInstrumentation().waitForIdleSync();assertTrue(events.contains("projectionChanged"));
            events.clear();scenario.onActivity(activity->{bridge.suspend(activity);bridge.returned(activity);});
            InstrumentationRegistry.getInstrumentation().waitForIdleSync();assertTrue(events.isEmpty());
            scenario.onActivity(bridge::resume);InstrumentationRegistry.getInstrumentation().waitForIdleSync();
            assertTrue(events.contains("projectionChanged"));
            assertFalse(app().catalogRuntime().gameCenterSnapshot().rows().isEmpty());
            invoke(bridge,"detach",host,Map.of());
        }
    }
    @Test public void sourceObservationDoesNotWaitForBlockedCatalogRequest() throws Exception {
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            AtomicReference<ProductBridge> adapter=new AtomicReference<>();
            scenario.onActivity(activity->{var b=new ProductBridge(app(),new MethodChannel(app().foundationEngine().getDartExecutor().getBinaryMessenger(),"flynes/product-observe-test"));b.attach(activity);adapter.set(b);});
            var bridge=adapter.get();var boot=invoke(bridge,"bootstrap",0,Map.of());long host=((Number)boot.get("hostGeneration")).longValue();
            var field=ProductBridge.class.getDeclaredField("worker");field.setAccessible(true);
            CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
            ((ExecutorService)field.get(bridge)).execute(()->{entered.countDown();try{release.await(10,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}});
            assertTrue(entered.await(2,TimeUnit.SECONDS));
            CompletableFuture<Map<?,?>> observed=CompletableFuture.supplyAsync(()->{try{return invoke(bridge,"sources",host,Map.of());}catch(Exception e){throw new CompletionException(e);}});
            try {assertFalse("Sources must remain observable while mutation requests wait",((List<?>)observed.get(2,TimeUnit.SECONDS).get("items")).isEmpty());}
            finally {release.countDown();invoke(bridge,"detach",host,Map.of());}
        }
    }
    private final AtomicLong requests=new AtomicLong();
    private FlyNesApplication app(){return ApplicationProvider.getApplicationContext();}
    private Map<?,?> invoke(ProductBridge bridge,String method,long generation,Map<String,Object> args)throws Exception {
        var values=new HashMap<String,Object>(args);long request=requests.incrementAndGet();
        values.put("requestId",request);values.put("hostGeneration",generation);
        CompletableFuture<Map<?,?>> result=new CompletableFuture<>();
        InstrumentationRegistry.getInstrumentation().runOnMainSync(()->bridge.onMethodCall(new MethodCall(method,values),new MethodChannel.Result(){
            public void success(Object raw){result.complete((Map<?,?>)raw);}
            public void error(String code,String message,Object details){result.completeExceptionally(new IllegalStateException(code));}
            public void notImplemented(){result.completeExceptionally(new IllegalStateException("not_implemented"));}
        }));
        Map<?,?> reply=result.get(30,TimeUnit.SECONDS);assertEquals(request,((Number)reply.get("requestId")).longValue());return reply;
    }
    @Test public void snapshotWindowsUseSharedManifestFactsAndRealGeneration()throws Exception {
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            AtomicReference<ProductBridge> adapter=new AtomicReference<>();
            scenario.onActivity(activity->{var bridge=new ProductBridge(app(),new MethodChannel(app().foundationEngine().getDartExecutor().getBinaryMessenger(),"flynes/product-test"));bridge.attach(activity);adapter.set(bridge);});
            var bridge=adapter.get();var bootstrap=invoke(bridge,"bootstrap",0,Map.of());long host=((Number)bootstrap.get("hostGeneration")).longValue();
            assertEquals(1,bootstrap.get("protocolVersion"));assertEquals(BuildConfig.VERSION_NAME,bootstrap.get("version"));
            var catalog=invoke(bridge,"catalogQuery",host,Map.of("category","builtin","query","","multiplayerOnly",false,"selectedId",""));
            assertEquals(app().catalogRuntime().gameCenterSnapshot().nativeGeneration(),((Number)catalog.get("catalogGeneration")).longValue());
            List<?> items=(List<?>)catalog.get("items");assertFalse(items.isEmpty());assertTrue(items.size()<=128);
            String id=(String)((Map<?,?>)items.get(items.size()-1)).get("canonicalId");
            catalog=invoke(bridge,"catalogQuery",host,Map.of("category","builtin","query","","multiplayerOnly",false,"selectedId",id));
            var empty=invoke(bridge,"catalogWindow",host,Map.of("viewRevision",catalog.get("viewRevision"),"catalogGeneration",catalog.get("catalogGeneration"),"offset",999,"limit",1));
            assertEquals(id,empty.get("selectedId"));assertTrue(((List<?>)empty.get("items")).isEmpty());
            var row=invoke(bridge,"catalogItem",host,Map.of("canonicalId",id));assertEquals(id,row.get("canonicalId"));assertTrue((Boolean)row.get("builtin"));
            var multi=invoke(bridge,"catalogQuery",host,Map.of("category","builtin","query","","multiplayerOnly",true,"selectedId",""));
            assertTrue("Manifest canonical metadata must use the scanned hash IDs",((Number)multi.get("total")).intValue()>0);
            for(Object item:(List<?>)multi.get("items"))assertEquals(true,((Map<?,?>)item).get("multiplayerSupported"));
            var licenses=invoke(bridge,"licenses",host,Map.of());assertFalse(((List<?>)licenses.get("items")).isEmpty());
            String license=(String)((Map<?,?>)((List<?>)licenses.get("items")).get(0)).get("id");
            assertFalse(((String)invoke(bridge,"licenseText",host,Map.of("id",license)).get("text")).isEmpty());
            try{invoke(bridge,"settings",host+1,Map.of());fail("Stale host accepted");}catch(ExecutionException expected){assertEquals("stale_host",expected.getCause().getMessage());}
            var settings=invoke(bridge,"settings",host,Map.of());assertTrue(((Map<?,?>)settings.get("values")).get("audioEnabled") instanceof Boolean);
            assertEquals(app().controlLayoutBackend().controlLayoutGet().equals(com.flynes.emu.input.ControlLayoutV2.recommended().encode())?"recommended":"custom",settings.get("layoutSummary"));
            invoke(bridge,"detach",host,Map.of());assertFalse(app().catalogRuntime().gameCenterSnapshot().rows().isEmpty());
        }
    }
    @Test public void pausedSettingsReturnsToSameGameAndEngineThenRestoresHall()throws Exception {pausedSettingsRoundTrip(false);}
    @Test public void pausedLanguageChangeRetainsGameCoreAndClock()throws Exception {pausedSettingsRoundTrip(true);}
    private void pausedSettingsRoundTrip(boolean changeLanguage)throws Exception {
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            var bridge=app().productBridge();var bootstrap=invoke(bridge,"bootstrap",0,Map.of());long generation=((Number)bootstrap.get("hostGeneration")).longValue();
            app().catalogRuntime().nativeReady().get(30,TimeUnit.SECONDS);
            String id=app().catalogRuntime().gameCenterSnapshot().rows().stream().filter(r->r.builtin()&&r.launchable()).findFirst().orElseThrow().canonicalId();
            var engine=app().foundationEngine();
            CompletableFuture<Map<?,?>> launched=CompletableFuture.supplyAsync(()->{try{return invoke(bridge,"launch",generation,Map.of("canonicalId",id,"purpose","single"));}catch(Exception e){throw new CompletionException(e);}});
            MainActivity game=awaitActivity(MainActivity.class);
            var field=MainActivity.class.getDeclaredField("historyClock");field.setAccessible(true);
            var clock=(com.flynes.emu.save.HistoryClock)field.get(game);SystemClock.sleep(300);
            InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                if(changeLanguage) {
                    game.findViewById(R.id.pause_button).performClick();
                    game.findViewById(R.id.pause_settings).performClick();
                } else game.startActivity(ProductRoutes.intent(game,"settings").putExtra("product_return_token","game"));
            });
            FlutterFoundationActivity settings=awaitActivity(FlutterFoundationActivity.class);
            long stopped=clock.playedMs();SystemClock.sleep(300);assertEquals("Settings must stop the real media/save clock",stopped,clock.playedMs());
            assertEquals(0,FlutterFoundationIntegrationTest.audioThreads());
            assertSame(engine,app().foundationEngine());
            var context=invoke(bridge,"bootstrap",0,Map.of());assertEquals("settings",((Map<?,?>)context.get("context")).get("route"));
            String previousLocale=ProductSettings.read(app().settingsRepository()).localeTag();
            if(changeLanguage) {
                invoke(bridge,"patchSetting",((Number)context.get("hostGeneration")).longValue(),
                        Map.of("key","localeTag","value",previousLocale.startsWith("zh")?"en":"zh-Hans"));
                InstrumentationRegistry.getInstrumentation().waitForIdleSync();
                assertEquals("Language update must not advance the paused save clock",stopped,clock.playedMs());
            }
            invoke(bridge,"closeHost",((Number)context.get("hostGeneration")).longValue(),Map.of());
            assertSame("Returning must retain the native game Activity",game,awaitActivity(MainActivity.class));
            assertSame(clock,field.get(game));
            if(changeLanguage)InstrumentationRegistry.getInstrumentation().runOnMainSync(()->
                    assertEquals(game.getString(R.string.open_pause),game.findViewById(R.id.pause_button).getContentDescription()));
            InstrumentationRegistry.getInstrumentation().runOnMainSync(game::finish);
            awaitActivity(FlutterFoundationActivity.class);
            var hall=invoke(bridge,"bootstrap",0,Map.of());assertEquals("hall",((Map<?,?>)hall.get("context")).get("route"));
            assertSame(engine,app().foundationEngine());
            assertEquals("returned",launched.get(30,TimeUnit.SECONDS).get("status"));
            if(changeLanguage)invoke(bridge,"patchSetting",((Number)hall.get("hostGeneration")).longValue(),Map.of("key","localeTag","value",previousLocale));
        }
    }
    @Test public void twentyPauseSettingsLayoutRoundTripsRetainOwners()throws Exception {
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            var bridge=app().productBridge();var bootstrap=invoke(bridge,"bootstrap",0,Map.of());
            long initialHost=((Number)bootstrap.get("hostGeneration")).longValue();
            app().catalogRuntime().nativeReady().get(30,TimeUnit.SECONDS);
            String id=app().catalogRuntime().gameCenterSnapshot().rows().stream().filter(r->r.builtin()&&r.launchable()).findFirst().orElseThrow().canonicalId();
            var engine=app().foundationEngine();
            CompletableFuture<Map<?,?>> launched=CompletableFuture.supplyAsync(()->{try{return invoke(bridge,"launch",initialHost,Map.of("canonicalId",id,"purpose","single"));}catch(Exception e){throw new CompletionException(e);}});
            MainActivity game=awaitActivity(MainActivity.class);
            var clockField=MainActivity.class.getDeclaredField("historyClock");clockField.setAccessible(true);
            var coreField=MainActivity.class.getDeclaredField("core");coreField.setAccessible(true);
            var clock=(com.flynes.emu.save.HistoryClock)clockField.get(game);Object core=coreField.get(game);
            var weakHosts=new ArrayList<java.lang.ref.WeakReference<FlutterFoundationActivity>>();
            var weakLayouts=new ArrayList<java.lang.ref.WeakReference<ControlLayoutActivity>>();
            for(int cycle=1;cycle<=20;cycle++) {
                long before=clock.playedMs(),deadline=SystemClock.elapsedRealtime()+5000;
                while(clock.playedMs()<=before&&SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(20);
                assertTrue("Real game progresses before pause cycle "+cycle,clock.playedMs()>before);
                assertEquals(1,FlutterFoundationIntegrationTest.audioThreads());
                InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                    game.findViewById(R.id.pause_button).performClick();
                    game.findViewById(R.id.pause_settings).performClick();
                });
                FlutterFoundationActivity settings=awaitActivity(FlutterFoundationActivity.class);
                weakHosts.add(new java.lang.ref.WeakReference<>(settings));
                long paused=clock.playedMs();
                var context=invoke(bridge,"bootstrap",0,Map.of());
                assertEquals("settings",((Map<?,?>)context.get("context")).get("route"));
                assertSame(engine,app().foundationEngine());assertEquals(0,FlutterFoundationIntegrationTest.audioThreads());
                long settingsHost=((Number)context.get("hostGeneration")).longValue();
                var layoutBefore=new com.flynes.emu.settings.ControlLayoutRepository(app().controlLayoutBackend()).load().encode();
                CompletableFuture<Map<?,?>> opening=CompletableFuture.supplyAsync(()->{try{return invoke(bridge,"openNative",settingsHost,Map.of("page","layout"));}catch(Exception e){throw new CompletionException(e);}});
                ControlLayoutActivity layout=awaitActivity(ControlLayoutActivity.class);weakLayouts.add(new java.lang.ref.WeakReference<>(layout));
                final int action=cycle%2==0?R.id.control_layout_save:R.id.control_layout_discard;
                InstrumentationRegistry.getInstrumentation().runOnMainSync(()->layout.findViewById(action).performClick());
                opening.get(15,TimeUnit.SECONDS);
                assertSame("Layout must return to same Flutter settings host",settings,awaitActivity(FlutterFoundationActivity.class));
                assertEquals(layoutBefore,new com.flynes.emu.settings.ControlLayoutRepository(app().controlLayoutBackend()).load().encode());
                assertEquals("Settings/layout never advances single-player save time",paused,clock.playedMs());
                assertEquals(0,FlutterFoundationIntegrationTest.audioThreads());
                AtomicLong attached=new AtomicLong();
                InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                    var monitor=androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance();
                    for(var stage:androidx.test.runner.lifecycle.Stage.values())for(var activity:monitor.getActivitiesInStage(stage))
                        if(activity instanceof FlutterFoundationActivity)attached.addAndGet(attachedFlutterViews(activity.getWindow().getDecorView()));
                });
                assertEquals("Exactly one attached Flutter view",1,attached.get());
                if(cycle==1||cycle==20)FlutterFoundationIntegrationTest.screenshot("g2-pause-settings-"+cycle+".png");
                context=invoke(bridge,"bootstrap",0,Map.of());
                invoke(bridge,"closeHost",((Number)context.get("hostGeneration")).longValue(),Map.of());
                assertSame(game,awaitActivity(MainActivity.class));assertSame(core,coreField.get(game));assertSame(clock,clockField.get(game));
                assertSame(engine,app().foundationEngine());
                android.util.Log.i("G2RoundTrip","PAUSE_LAYOUT cycle="+cycle+" sameCore=true sameClock=true engines=1 attachedViews=1 pausedAudio=0");
            }
            InstrumentationRegistry.getInstrumentation().runOnMainSync(game::finish);
            awaitActivity(FlutterFoundationActivity.class);launched.get(30,TimeUnit.SECONDS);
            long deadline=SystemClock.elapsedRealtime()+10000,retained;
            do {System.gc();System.runFinalization();SystemClock.sleep(100);
                retained=weakHosts.stream().filter(r->r.get()!=null).count()+weakLayouts.stream().filter(r->r.get()!=null).count();
            }while(retained>2&&SystemClock.elapsedRealtime()<deadline);
            assertTrue("Only final stack locals may retain destroyed hosts: "+retained,retained<=2);
            assertEquals(0,FlutterFoundationIntegrationTest.audioThreads());
            android.util.Log.i("G2RoundTrip","PAUSE_LAYOUT completed=20 retainedDestroyedOwners="+retained);
        }
    }
    private static int attachedFlutterViews(android.view.View view) {
        int count=view instanceof io.flutter.embedding.android.FlutterView flutter&&flutter.isAttachedToFlutterEngine()?1:0;
        if(view instanceof android.view.ViewGroup group)for(int i=0;i<group.getChildCount();i++)count+=attachedFlutterViews(group.getChildAt(i));
        return count;
    }
    @Test public void cancellingRealSafPickerDoesNotRegisterOrScanASource()throws Exception {
        try(var scenario=ActivityScenario.launch(FlutterFoundationActivity.class)) {
            var bridge=app().productBridge();var bootstrap=invoke(bridge,"bootstrap",0,Map.of());
            long host=((Number)bootstrap.get("hostGeneration")).longValue();
            var runtime=app().catalogRuntime();long generation=runtime.gameCenterSnapshot().nativeGeneration();
            var before=new HashSet<>(runtime.stateSnapshot().sources().keySet());
            CompletableFuture<Map<?,?>> picking=CompletableFuture.supplyAsync(()->{try{return invoke(bridge,"pickSource",host,Map.of("kind","file"));}catch(Exception e){throw new CompletionException(e);}});
            long deadline=SystemClock.elapsedRealtime()+10000;boolean picker=false;
            do{var root=InstrumentationRegistry.getInstrumentation().getUiAutomation().getRootInActiveWindow();
                if(root!=null&&String.valueOf(root.getPackageName()).contains("documentsui")){picker=true;break;}SystemClock.sleep(50);
            }while(SystemClock.elapsedRealtime()<deadline);
            assertTrue("The real Android SAF UI must be visible",picker);
            InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK);
            assertEquals("cancelled",picking.get(15,TimeUnit.SECONDS).get("status"));
            assertEquals(before,runtime.stateSnapshot().sources().keySet());
            assertEquals(generation,runtime.gameCenterSnapshot().nativeGeneration());
        }
    }
    private <T> T awaitActivity(Class<T> type)throws Exception {
        long deadline=SystemClock.elapsedRealtime()+15000;AtomicReference<T> result=new AtomicReference<>();
        do{InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
            for(var activity:androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED))
                if(type.isInstance(activity))result.set(type.cast(activity));});
            if(result.get()!=null)return result.get();SystemClock.sleep(50);
        }while(SystemClock.elapsedRealtime()<deadline);throw new AssertionError("Activity unavailable: "+type.getSimpleName());
    }
}
