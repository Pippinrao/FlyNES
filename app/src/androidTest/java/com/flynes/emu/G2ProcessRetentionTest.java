package com.flynes.emu;

import static org.junit.Assert.*;
import android.content.Intent;
import android.os.SystemClock;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.platform.app.InstrumentationRegistry;
import com.flynes.emu.launch.ExactRomLoader;
import com.flynes.emu.launch.LaunchRequest;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import org.json.*;
import org.junit.Test;

/** Three explicit invocations separated by process termination, without clearing app data. */
public final class G2ProcessRetentionTest {
    @Test public void persistedProductStateInFreshLauncherHost() throws Exception {
        var args=InstrumentationRegistry.getArguments();
        String phase=args.getString("g2ProcessPhase","");
        org.junit.Assume.assumeTrue("Explicit seed / verify / cleanup only",List.of("seed","verify","cleanup").contains(phase));
        String run=args.getString("g2ProcessRun","");assertTrue(run.matches("[a-zA-Z0-9_-]{8,64}"));
        FlyNesApplication app=ApplicationProvider.getApplicationContext();
        assertTrue("Task simulator only",android.os.Build.FINGERPRINT.contains("generic")||android.os.Build.FINGERPRINT.contains("emu64"));
        app.catalogRuntime().nativeReady().get(30,TimeUnit.SECONDS);
        File fixture=new File(app.getExternalFilesDir(null),"g2-process-"+run+".json");
        if(phase.equals("cleanup")) {
            JSONObject saved=new JSONObject(new String(Files.readAllBytes(fixture.toPath()),java.nio.charset.StandardCharsets.UTF_8));
            var before=saved.getJSONObject("originalSettings");
            Throwable cleanup=G2FixtureCleanup.all(
                ()->assertTrue(G2PerformanceUi.restore(app,map(saved.getJSONObject("originalNavigation")))),
                ()->assertTrue(ProductSettings.save(app.settingsRepository(),"audioEnabled",before.getBoolean("audioEnabled"))),
                ()->assertTrue(ProductSettings.save(app.settingsRepository(),"autosaveEnabled",before.getBoolean("autosaveEnabled"))),
                ()->assertEquals(saved.getJSONObject("sources").toString(),sources(app).toString()));
            saved.put("restored",cleanup==null);if(cleanup!=null)saved.put("cleanupFailure",cleanup.toString());
            Files.write(fixture.toPath(),saved.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            if(cleanup!=null)throw new AssertionError("Process fixture cleanup failed",cleanup);
            return;
        }
        JSONObject saved;
        if(phase.equals("seed")) {
            assertFalse("Never overwrite a prior evidence/restore record",fixture.exists());
            saved=new JSONObject().put("originalNavigation",new JSONObject(app.getSharedPreferences("game_center_ui",0).getAll()))
                    .put("originalSettings",new JSONObject(ProductSettings.values(ProductSettings.read(app.settingsRepository()))))
                    .put("sources",sources(app));
            // Write the restore record before the first change, so a failed assertion is recoverable.
            Files.write(fixture.toPath(),saved.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
        } else saved=new JSONObject(new String(Files.readAllBytes(fixture.toPath()),java.nio.charset.StandardCharsets.UTF_8));
        launchNormally(app);
        try {
            var bootstrap=invoke(app,"bootstrap",Map.of());
            if(phase.equals("seed")) {
                var catalog=invoke(app,"catalogQuery",Map.of("category","builtin","query","","multiplayerOnly",true,"selectedId",""));
                var rows=(List<?>)catalog.get("items");assertTrue("Two-player manifest fixture",rows.size()>=2);
                var first=(Map<?,?>)rows.get(0);var last=(Map<?,?>)rows.get(rows.size()-1);
                var selections=new LinkedHashMap<String,Object>();
                selections.put("recent",first.get("canonicalId"));selections.put("favorites",last.get("canonicalId"));
                selections.put("all",first.get("canonicalId"));selections.put("builtin",last.get("canonicalId"));
                invoke(app,"saveNavigation",Map.of("category","builtin","multiplayerOnly",true,"selections",selections));
                var original=saved.getJSONObject("originalSettings");
                invoke(app,"patchSetting",Map.of("key","audioEnabled","value",!original.getBoolean("audioEnabled")));
                invoke(app,"patchSetting",Map.of("key","autosaveEnabled","value",!original.getBoolean("autosaveEnabled")));
                var persisted=invoke(app,"bootstrap",Map.of());
                saved.put("preferences",new JSONObject((Map<?,?>)persisted.get("preferences")))
                        .put("settings",new JSONObject(ProductSettings.values(ProductSettings.read(app.settingsRepository()))))
                        .put("seedPid",android.os.Process.myPid()).put("seedInstanceId",bootstrap.get("instanceId"))
                        .put("selectedTitleEn",last.get("titleEn")).put("selectedTitleZhHans",last.get("titleZhHans"));
                Files.write(fixture.toPath(),saved.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            } else {
                assertNotEquals("A recreation is not process death",saved.getInt("seedPid"),android.os.Process.myPid());
                assertNotEquals(saved.getString("seedInstanceId"),bootstrap.get("instanceId"));
                assertEquals(map(saved.getJSONObject("preferences")),bootstrap.get("preferences"));
                assertEquals(map(saved.getJSONObject("settings")),ProductSettings.values(ProductSettings.read(app.settingsRepository())));
                assertEquals(saved.getJSONObject("sources").toString(),sources(app).toString());
                assertNull("No fabricated nearby connection",app.nearbyMvpOwner().session());
                assertNull("No secondary nearby owner initialized",app.nearbySessionOwner());
                assertEquals("No game/audio resumed from persisted navigation",0,FlutterFoundationIntegrationTest.audioThreads());
                InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
                    var monitor=androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance();
                    for(var stage:androidx.test.runner.lifecycle.Stage.values())for(var activity:monitor.getActivitiesInStage(stage))
                        assertFalse("No fabricated native game Activity",activity instanceof MainActivity&&!activity.isDestroyed());
                });
                String en=saved.getString("selectedTitleEn"),zh=saved.getString("selectedTitleZhHans");
                awaitNode(n->label(n).equals(en)||label(n).equals(zh));
                awaitNode(n->n.isChecked()&&(label(n).equals("Two-player")||label(n).equals("双人支持")));
                saved.put("verifyPid",android.os.Process.myPid()).put("verifyInstanceId",bootstrap.get("instanceId"))
                        .put("verified",true).put("observationBoundary","fresh instrumentation process, ordinary PackageManager MAIN/LAUNCHER intent; external normal launch separately recorded");
                Files.write(fixture.toPath(),saved.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
                FlutterFoundationIntegrationTest.screenshot("g2-process-verified.png");
            }
        } finally { finishHosts(); }
    }
    static void launchNormally(FlyNesApplication app) throws Exception {
        Intent intent=app.getPackageManager().getLaunchIntentForPackage(app.getPackageName());
        assertNotNull(intent);assertEquals(Intent.ACTION_MAIN,intent.getAction());assertTrue(intent.hasCategory(Intent.CATEGORY_LAUNCHER));
        assertEquals(FlutterFoundationActivity.class.getName(),intent.getComponent().getClassName());
        InstrumentationRegistry.getInstrumentation().runOnMainSync(()->app.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)));
        awaitNode(G2PerformanceUi::primary);
    }
    static Map<?,?> invoke(FlyNesApplication app,String method,Map<String,Object> values)throws Exception {
        var args=new HashMap<String,Object>(values);args.put("requestId",System.nanoTime());
        var bridge=app.productBridge();assertNotNull(bridge);
        if(!method.equals("bootstrap")) {
            var context=invoke(app,"bootstrap",Map.of());args.put("hostGeneration",context.get("hostGeneration"));
        } else args.put("hostGeneration",0L);
        CompletableFuture<Map<?,?>> result=new CompletableFuture<>();
        InstrumentationRegistry.getInstrumentation().runOnMainSync(()->bridge.onMethodCall(new MethodCall(method,args),new MethodChannel.Result(){
            public void success(Object value){result.complete((Map<?,?>)value);}
            public void error(String code,String message,Object details){result.completeExceptionally(new AssertionError(code));}
            public void notImplemented(){result.completeExceptionally(new AssertionError("not implemented: "+method));}
        }));return result.get(30,TimeUnit.SECONDS);
    }
    static android.view.accessibility.AccessibilityNodeInfo awaitNode(java.util.function.Predicate<android.view.accessibility.AccessibilityNodeInfo> predicate) {
        long deadline=SystemClock.elapsedRealtime()+30000;
        do {var node=G2PerformanceUi.find(InstrumentationRegistry.getInstrumentation().getUiAutomation().getRootInActiveWindow(),n->G2PerformanceUi.visible(n)&&predicate.test(n));
            if(node!=null)return node;SystemClock.sleep(25);
        }while(SystemClock.elapsedRealtime()<deadline);throw new AssertionError("Expected real visible product node");
    }
    static String label(android.view.accessibility.AccessibilityNodeInfo node){
        return node.getContentDescription()!=null?node.getContentDescription().toString():String.valueOf(node.getText());
    }
    static void finishHosts(){
        InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{
            var monitor=androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance();
            Set<android.app.Activity> activities=new HashSet<>();for(var stage:androidx.test.runner.lifecycle.Stage.values())activities.addAll(monitor.getActivitiesInStage(stage));
            for(var activity:activities)if(!activity.isDestroyed())activity.finish();
        });InstrumentationRegistry.getInstrumentation().waitForIdleSync();
    }
    static Map<String,Object> map(JSONObject object)throws JSONException {
        Map<String,Object> values=new LinkedHashMap<>();var keys=object.keys();while(keys.hasNext()){String key=keys.next();Object value=object.get(key);values.put(key,value instanceof JSONObject?map((JSONObject)value):value);}return values;
    }
    private static JSONObject sources(FlyNesApplication app)throws Exception {
        var runtime=app.catalogRuntime();var result=new JSONObject();
        var rows=new JSONArray();for(var row:runtime.productSourcesSnapshot().stream().sorted(Comparator.comparing(r->r.uuid())).toList())
            rows.put(new JSONObject().put("uuid",row.uuid()).put("type",row.source().type().name()).put("permission",row.source().permissionState().name()).put("count",row.count()));
        result.put("rows",rows);
        var grants=new JSONArray();for(var grant:app.getContentResolver().getPersistedUriPermissions().stream().sorted(Comparator.comparing(g->g.getUri().toString())).toList())
            grants.put(digest((grant.getUri()+":"+grant.isReadPermission()+":"+grant.isWritePermission()).getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        assertTrue("Existing actual SAF grant required; do not import substitute",grants.length()>0);result.put("grants",grants);
        var source=runtime.productSourcesSnapshot().stream().filter(r->r.source().type()!=com.flynes.emu.catalog.RomSource.Type.BUILTIN&&r.source().isUsable()&&r.count()>0).findFirst().orElseThrow();
        var variant=runtime.gameCatalog().canonicalEntries().stream().flatMap(g->g.variants().stream()).filter(v->v.sourceId().equals(source.id())&&v.isLaunchable()).findFirst().orElseThrow();
        result.put("readableUuid",source.uuid()).put("payloadSha256",digest(new ExactRomLoader(runtime.streamOpener()).load(LaunchRequest.forVariant(variant))));
        return result;
    }
    static String digest(byte[] bytes)throws Exception{return java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(bytes));}
}
