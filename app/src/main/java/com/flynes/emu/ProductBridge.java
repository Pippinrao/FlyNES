package com.flynes.emu;

import android.app.Activity;
import android.content.*;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import com.flynes.emu.catalog.BuiltinGames;
import com.flynes.emu.catalog.RomSource;
import com.flynes.emu.catalog.android.AndroidCatalogRuntime;
import com.flynes.emu.cover.AndroidCoverRepository;
import com.flynes.emu.gamecenter.GameCenterSnapshot;
import com.flynes.emu.settings.*;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

/** Process-scoped UI adapter. Native catalog, save, scan and nearby owners outlive every host. */
final class ProductBridge implements MethodChannel.MethodCallHandler {
    static final int ROUTE=7201, PICKER=7202;
    static final String ROUTE_EXTRA="product_route", PURPOSE_EXTRA="product_purpose";
    private final FlyNesApplication app;
    private final MethodChannel channel;
    private final AndroidCoverRepository covers;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor(r->new Thread(r,"flynes-product"));
    private final ExecutorService sourceWorker=Executors.newSingleThreadExecutor(r->new Thread(r,"flynes-source-requests"));
    private final ExecutorService namesWorker=Executors.newSingleThreadExecutor(r->new Thread(r,"flynes-source-names"));
    private final ProductSourceNames sourceNames;
    private final ProductHostObservation<FlutterFoundationActivity> observation=new ProductHostObservation<>();
    private AutoCloseable scanSubscription;
    private final String instance=UUID.randomUUID().toString();
    private FlutterFoundationActivity host;
    private long generation,revision;
    private AndroidCatalogRuntime.ProductCapture capture;
    private int category;
    private boolean multiplayer;
    private String query="",selected="";
    private String[][] metadata=new String[0][];
    private int[] eligibility=new int[0];
    private int profile;
    private final Map<String,Boolean> supported=new HashMap<>();
    private GameCenterSnapshot factsSnapshot;
    private Map<String,BuiltinGames.Entry> factsByCanonical=Map.of();
    private final Map<FlutterFoundationActivity,Request> pendingRoutes=new IdentityHashMap<>();
    private record PickerRequest(Request request,String uuid) {}
    private final ProductPicker<PickerRequest> picker=new ProductPicker<>();
    private final NearbyMvpOwner nearbyOwner;
    @FunctionalInterface interface NearbyPortFactory {
        ProductNearbySelection.Port create(String canonicalId,NearbyMvpSession session,Runnable complete);
    }
    private final NearbyPortFactory nearbyPorts;

    ProductBridge(FlyNesApplication app,MethodChannel channel) {
        this(app,channel,app.nearbyMvpOwner(),null);
    }
    ProductBridge(FlyNesApplication app,MethodChannel channel,NearbyMvpOwner nearbyOwner,NearbyPortFactory nearbyPorts) {
        this.app=app;this.channel=channel;covers=new AndroidCoverRepository(app);
        var namePrefs=app.getSharedPreferences("flynes_product_source_names",Context.MODE_PRIVATE);
        sourceNames=new ProductSourceNames(new ProductSourceNames.Store() {
            public ProductSourceNames.Entry read(String uuid) {
                var saved=namePrefs.getAll();Object name=saved.get(uuid+".name"),locator=saved.get(uuid+".locator");
                return name instanceof String n&&locator instanceof String l?new ProductSourceNames.Entry(l,n):null;
            }
            public void write(String uuid,ProductSourceNames.Entry value) {
                if(!namePrefs.edit().putString(uuid+".name",value.name()).putString(uuid+".locator",value.locator()).commit())
                    throw new IllegalStateException("source_name_write_failed");
            }
            public void remove(String uuid) {namePrefs.edit().remove(uuid+".name").remove(uuid+".locator").apply();}
        },namesWorker,this::sourceName,()->changed("sources"));
        this.nearbyOwner=nearbyOwner;this.nearbyPorts=nearbyPorts==null?this::nearbyPort:nearbyPorts;
        channel.setMethodCallHandler(this);
    }
    void attach(FlutterFoundationActivity activity) {
        if(host==activity)return;
        invalidateNearby(host);
        host=activity;generation++;
        observation.attach(activity);subscribeScans();
        channel.invokeMethod("contextChanged",ProductEnvelope.reply(0,generation,instance,Map.of("context",context())));
    }
    void detach(FlutterFoundationActivity activity) { if(host==activity){invalidateNearby(activity);observation.detach(activity);unsubscribeScans();host=null;} }
    void suspend(FlutterFoundationActivity activity){if(host==activity){invalidateNearby(activity);observation.suspend(activity);unsubscribeScans();}}
    void resume(FlutterFoundationActivity activity){if(host==activity){observation.resume(activity);subscribeScans();changed("sources","catalog","resume","settings");}}
    private void subscribeScans(){if(scanSubscription==null&&observation.accepts(observation.ticket())) {
        var observedGeneration=new java.util.concurrent.atomic.AtomicLong(app.catalogRuntime().gameCenterSnapshot().nativeGeneration());
        scanSubscription=app.catalogRuntime().scanOperations().observe(()->{
            long current=app.catalogRuntime().gameCenterSnapshot().nativeGeneration();
            if(observedGeneration.getAndSet(current)!=current)changed("sources","catalog");
            else changed("sources");
        });
    }}
    private void unsubscribeScans(){if(scanSubscription!=null){try{scanSubscription.close();}catch(Exception ignored){}scanSubscription=null;}}
    void returned(FlutterFoundationActivity activity) {
        invalidateNearby(activity);
        Request request=pendingRoutes.remove(activity);
        if(request!=null)request.success(Map.of("status","returned"));
        changed("catalog","resume","settings","sources");
    }
    private Map<String,Object> context() {
        Intent intent=host==null?new Intent():host.getIntent();
        String route=intent.getStringExtra(ROUTE_EXTRA),purpose=intent.getStringExtra(PURPOSE_EXTRA);
        return Map.of("route",route==null?"hall":route,"purpose","nearby".equals(purpose)?"nearby":"single",
                "returnToken",intent.getStringExtra("product_return_token")==null?"":intent.getStringExtra("product_return_token"),
                "presentationToken",host==null?"":host.presentationToken());
    }
    private final class Request {
        final MethodChannel.Result result;final Object id;final long lease;
        final ProductNearbySelection.CommandLease nearbyCommands=new ProductNearbySelection.CommandLease();
        Request(MethodCall call,MethodChannel.Result result) {this.result=result;id=call.argument("requestId");lease=generation;}
        void success(Map<String,?> body) {main.post(()->result.success(ProductEnvelope.reply(id,lease,instance,body)));}
        void error(String code) {main.post(()->result.error(code,code,null));}
    }
    private static final class Failure extends RuntimeException {
        final String code; Failure(String code){this.code=code;}
    }
    private void work(Request request,Callable<Map<String,?>> action) {
        worker.execute(()->{try {app.catalogRuntime().nativeReady().get();request.success(action.call());}
            catch(Failure e){request.error(e.code);} catch(IllegalArgumentException e){request.error("invalid_argument");}
            catch(Exception e){request.error(errorCode(e));}});
    }
    private static String errorCode(Throwable failure) {
        for(Throwable cause=failure;cause!=null;cause=cause.getCause()) {
            if(cause instanceof Failure product)return product.code;
            if(cause instanceof ProductNearbySelection.Failure nearby)return nearby.code;
            if(cause instanceof java.util.concurrent.CancellationException)return "cancelled";
            if(cause instanceof com.flynes.emu.catalog.android.ProductSourceTransactions.Failure source)return source.code();
            if(cause instanceof com.flynes.emu.catalog.android.AndroidUuidSafMap.PersistenceFailure)return "source_write_failed";
        }
        return "native_unavailable";
    }
    @Override public void onMethodCall(MethodCall call,MethodChannel.Result result) {
        Object incoming=call.argument("hostGeneration");
        if(!(incoming instanceof Number n)||call.argument("requestId")==null
                ||!ProductEnvelope.accepts(n.longValue(),generation,call.method.equals("bootstrap")||call.method.equals("presentationContext"))) {
            result.error("stale_host","stale_host",null);return;
        }
        Request request=new Request(call,result);
        try {
            switch(call.method) {
                case "presentationContext" -> request.success(Map.of("context",context(),
                        "locale",app.getResources().getConfiguration().getLocales().get(0).toLanguageTag()));
                case "presentationReady" -> {
                    Object frame=call.argument("frameNumber");
                    if(!(frame instanceof Number value))throw new IllegalArgumentException();
                    request.success(Map.of("accepted",requireHost().presentationReady(string(call,"token"),value.longValue())));
                }
                case "bootstrap" -> { observation.subscribe();subscribeScans();Map<String,Object> route=context();work(request,()->bootstrap(route)); }
                case "catalogQuery" -> work(request,()->catalogQuery(call));
                case "catalogWindow" -> work(request,()->catalogWindow(call));
                case "catalogItem" -> work(request,()->item(string(call,"canonicalId"),app.catalogRuntime().gameCenterSnapshot()));
                case "resumeCapability" -> work(request,()->app.resumeService().query(string(call,"canonicalId")));
                case "setFavorite" -> work(request,()->{
                    String id=string(call,"canonicalId");boolean value=bool(call,"value");
                    if(!app.catalogRuntime().setFavorite(id,value).get())throw new Failure("write_failed");
                    changed("catalog");return Map.of("canonicalId",id,"favorite",value,"catalogGeneration",app.catalogRuntime().gameCenterSnapshot().nativeGeneration());});
                case "saveNavigation" -> work(request,()->saveNavigation(call));
                case "sources" -> request.success(sources());
                case "pickSource" -> pickSource(call,request);
                case "scanSource" -> scanSource(string(call,"uuid"),request);
                case "cancelScan" -> {
                    String uuid=string(call,"uuid"),operation=string(call,"operationId");
                    String status=app.catalogRuntime().scanOperations().cancel(sourceId(uuid),operation);
                    if(!status.equals("accepted"))request.error(status);
                    else request.success(Map.of("status","cancelling","operationId",operation));
                }
                case "removeSource" -> work(request,()->{
                    String uuid=string(call,"uuid");String id=app.catalogRuntime().productSourceId(uuid);
                    if("builtin".equals(uuid))throw new Failure("source_protected");
                    app.catalogRuntime().removeSource(id).get();sourceNames.remove(uuid);changed("sources","catalog");return Map.of("status","completed","uuid",uuid);});
                case "settings" -> work(request,this::settings);
                case "patchSetting" -> work(request,()->patchSetting(call));
                case "resetControls" -> work(request,this::resetControls);
                case "previewHaptics" -> preview(request);
                case "licenses" -> work(request,this::licenses);
                case "licenseText" -> work(request,()->licenseText(string(call,"id")));
                case "launch" -> launch(call,request);
                case "openNative" -> openNative(call,request);
                case "openLink" -> {Uri uri=Uri.parse(string(call,"url"));if(!Set.of("http","https").contains(uri.getScheme())||uri.getHost()==null)throw new IllegalArgumentException();
                    requireHost().startActivity(new Intent(Intent.ACTION_VIEW,uri));request.success(Map.of("completed",true));}
                case "copyText" -> {((ClipboardManager)app.getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("FlyNES",string(call,"text")));request.success(Map.of("completed",true));}
                case "detach" -> {observation.unsubscribe();unsubscribeScans();request.success(Map.of("completed",true));}
                case "closeHost" -> {var activity=requireHost();invalidateNearby(activity);request.success(Map.of("completed",true));activity.finish();}
                default -> result.notImplemented();
            }
        } catch(Failure e){request.error(e.code);}catch(RuntimeException e){request.error("invalid_argument");}
    }
    private Map<String,?> bootstrap(Map<String,Object> route) {
        var result=new LinkedHashMap<String,Object>();result.put("protocolVersion",1);
        String locale=ProductSettings.read(app.settingsRepository()).localeTag();
        result.put("localePreference",locale);
        result.put("locale",locale.equals("system")?Locale.getDefault().toLanguageTag():locale);
        result.put("version",BuildConfig.VERSION_NAME);result.put("buildRevision",BuildConfig.BUILD_REVISION);
        result.put("context",route);result.put("capabilities",capabilities());result.put("preferences",navigation());return result;
    }
    private Map<String,Object> navigation() {
        var prefs=app.getSharedPreferences("game_center_ui",Context.MODE_PRIVATE);
        Map<String,Object> selections=new LinkedHashMap<>();
        for(String key:List.of("recent","favorites","all","builtin"))selections.put(key,prefs.getString("product.selected."+key,
                key.equals(prefs.getString("category","ALL").toLowerCase(Locale.ROOT))?prefs.getString("selected",""):""));
        return Map.of("category",prefs.getString("category","ALL").toLowerCase(Locale.ROOT),"multiplayerOnly",prefs.getBoolean("multiplayerOnly",false),"selections",selections);
    }
    private Map<String,?> saveNavigation(MethodCall call) {
        String category=string(call,"category");category(category);
        Object raw=call.argument("selections");if(!(raw instanceof Map<?,?> selections))throw new IllegalArgumentException();
        var edit=app.getSharedPreferences("game_center_ui",Context.MODE_PRIVATE).edit().putString("category",category.toUpperCase(Locale.ROOT))
                .putBoolean("multiplayerOnly",bool(call,"multiplayerOnly"));
        for(var entry:selections.entrySet()) {
            String key=String.valueOf(entry.getKey());category(key);
            if(!(entry.getValue() instanceof String value))throw new IllegalArgumentException();
            edit.putString("product.selected."+key,value);if(key.equals(category))edit.putString("selected",value);
        }
        if(!edit.commit())throw new Failure("write_failed");return navigation();
    }
    private static int category(String value) {return switch(value){case "recent"->0;case "favorites"->1;case "all"->2;case "builtin"->3;default->throw new IllegalArgumentException();};}
    private Map<String,?> catalogQuery(MethodCall call)throws Exception {
        if(capture!=null)app.catalogRuntime().releaseProduct(capture).get();
        capture=app.catalogRuntime().captureProduct().get();revision++;
        category=category(string(call,"category"));multiplayer=bool(call,"multiplayerOnly");
        query=optional(call,"query");selected=optional(call,"selectedId");
        var manifest=app.catalogRuntime().builtinGames();profile=(int)manifest.multiplayerProfileVersion();
        var facts=new ArrayList<String[]>();var flags=new ArrayList<Integer>();supported.clear();
        for(var row:capture.rows().rows()) {
            var builtin=builtinFacts(capture.rows()).get(row.canonicalId());
            if(builtin==null)continue;
            boolean eligible=builtin.multiplayerEligibility==BuiltinGames.MultiplayerEligibility.SUPPORTED;
            supported.put(row.canonicalId(),eligible);
            facts.add(new String[]{row.canonicalId(),builtin.titleEn,builtin.titleZhHans});
            flags.add(eligible?1:builtin.multiplayerEligibility==BuiltinGames.MultiplayerEligibility.UNSUPPORTED?0:2);
        }
        metadata=facts.toArray(new String[0][]);eligibility=flags.stream().mapToInt(Integer::intValue).toArray();
        return window(0,128);
    }
    private Map<String,?> catalogWindow(MethodCall call) {
        if(capture==null||number(call,"viewRevision")!=revision||number(call,"catalogGeneration")!=capture.rows().nativeGeneration())throw new Failure("snapshot_expired");
        return window(number(call,"offset"),Math.toIntExact(number(call,"limit")));
    }
    private Map<String,?> window(long offset,int limit) {
        var window=capture.nativeSnapshot().window(category,multiplayer,query,selected,offset,limit,metadata,eligibility,profile);
        if(window.generation()!=capture.rows().nativeGeneration())throw new Failure("snapshot_expired");
        List<Map<String,Object>> items=new ArrayList<>();for(String id:window.ids())items.add(item(id,capture.rows()));
        return Map.of("catalogGeneration",window.generation(),"viewRevision",revision,"total",window.total(),"offset",offset,"items",items,"selectedId",window.selectedId());
    }
    private Map<String,Object> item(String id,GameCenterSnapshot snapshot) {
        var row=GameCenterSnapshot.findRow(snapshot.rows(),id);if(row==null)throw new Failure("not_found");
        var v=new LinkedHashMap<String,Object>();v.put("canonicalId",id);v.put("titleEn",row.titleEn());v.put("titleZhHans",row.titleZhHans());
        v.put("available",row.launchable());v.put("unavailableReason",row.launchable()?"":"source_unavailable");
        String path=covers.existingPath(id);v.put("coverPath",path);v.put("coverRevision",path.isEmpty()?0:new java.io.File(path).lastModified());
        v.put("favorite",row.favorite());v.put("builtin",row.builtin());v.put("variantCount",row.variantCount());
        var builtin=builtinFacts(snapshot).get(id);
        v.put("multiplayerSupported",builtin!=null&&builtin.multiplayerEligibility==BuiltinGames.MultiplayerEligibility.SUPPORTED);return v;
    }
    private Map<String,BuiltinGames.Entry> builtinFacts(GameCenterSnapshot snapshot) {
        if(factsSnapshot!=snapshot) {
            factsByCanonical=ProductCatalogFacts.builtinMetadata(snapshot,app.catalogRuntime().builtinGames());
            factsSnapshot=snapshot;
        }
        return factsByCanonical;
    }
    private Map<String,?> settings() {return Map.of("values",ProductSettings.values(ProductSettings.read(app.settingsRepository())),"capabilities",capabilities(),"layoutSummary",app.controlLayoutBackend().controlLayoutGet().equals(com.flynes.emu.input.ControlLayoutV2.recommended().encode())?"recommended":"custom");}
    private Map<String,Object> capabilities() {
        var caps=new LinkedHashMap<String,Object>();
        caps.put("videoQualityPreset.3",Map.of("available",false,"reason","hardware_evidence_required"));
        caps.put("customTemporalMode.2",Map.of("available",false,"reason","hardware_evidence_required"));
        caps.put("customRefreshPolicy.2",Map.of("available",false,"reason","unsupported_option"));
        caps.put("customRefreshPolicy.4",Map.of("available",false,"reason","hardware_evidence_required"));
        caps.put("customRefreshPolicy.5",Map.of("available",false,"reason","hardware_evidence_required"));
        caps.put("cancelScan",Map.of("available",false,"reason","cancellation_unavailable"));
        return caps;
    }
    private Map<String,?> patchSetting(MethodCall call) {
        String key=string(call,"key");Object value=call.argument("value");
        if(capabilities().containsKey(key+"."+value))throw new Failure("capability_locked");
        var repository=app.settingsRepository();
        if(!ProductSettings.save(repository,key,value))throw new Failure("write_failed");
        if("localeTag".equals(key))main.post(()->{
            String tags="system".equals(value)?"":String.valueOf(value);
            // A Flutter-only process has no active AppCompat delegate from which
            // AppCompat can obtain LocaleManager on Android 13+. Use the app owner.
            if(android.os.Build.VERSION.SDK_INT>=33) {
                app.getSystemService(android.app.LocaleManager.class).setApplicationLocales(
                        android.os.LocaleList.forLanguageTags(tags));
            } else {
                androidx.appcompat.app.AppCompatDelegate.setApplicationLocales(
                        androidx.core.os.LocaleListCompat.forLanguageTags(tags));
            }
        });
        changed("settings");return settings();
    }
    private Map<String,?> resetControls() {
        var defaults=AppSettings.defaults();var repository=app.settingsRepository();
        if(!repository.updateCommitted(current -> current.toBuilder().layoutPreset(defaults.layoutPreset()).directionControlMode(defaults.directionControlMode())
                    .buttonScale(defaults.buttonScale()).verticalOffset(defaults.verticalOffset()).controlOpacity(defaults.controlOpacity())
                    .joystickScale(defaults.joystickScale()).deadZone(defaults.deadZone()).hapticLevel(defaults.hapticLevel()).distinctABHaptics(defaults.distinctABHaptics()).build()))throw new Failure("write_failed");
        if(!app.controlLayoutBackend().controlLayoutApply(com.flynes.emu.input.ControlLayoutV2.recommended().encode()))throw new Failure("write_failed");
        changed("settings");return settings();
    }
    private void preview(Request request) {
        var activity=requireHost();work(request,()->{var settings=ProductSettings.read(app.settingsRepository());main.post(()->{
            var view=activity.getWindow().getDecorView();var haptic=new com.flynes.emu.input.HapticController(view);
            haptic.configure(settings.hapticLevel(),settings.distinctABHaptics());haptic.feedback(com.flynes.emu.input.GamepadHitMap.Control.A);
            view.postDelayed(()->haptic.feedback(com.flynes.emu.input.GamepadHitMap.Control.B),260);
        });return Map.of("completed",true);});
    }
    private Map<String,?> licenses()throws Exception {
        String[] names=app.getAssets().list("licenses");if(names==null)names=new String[0];Arrays.sort(names);
        var items=new ArrayList<Map<String,Object>>();for(String name:names)if(name.endsWith(".txt")) {
            var game=app.catalogRuntime().builtinGames().byLicenseFile(name);
            String title=game!=null?game.titleEn:name.startsWith("nestopia")?"Nestopia UE":name.startsWith("own")?"FlyNES":name.startsWith("zlib")?"zlib":name;
            String url=game!=null?game.licenseSourceUrl:name.startsWith("nestopia")?"https://github.com/0ldsk00l/nestopia":name.startsWith("zlib")?"https://zlib.net/":"";
            items.add(Map.of("id",name,"title",title,"sourceUrl",url));
        }return Map.of("items",items);
    }
    private Map<String,?> licenseText(String id)throws Exception {
        if(id.contains("/")||id.contains("\\")||!id.endsWith(".txt"))throw new IllegalArgumentException();
        try(var input=app.getAssets().open("licenses/"+id);var output=new java.io.ByteArrayOutputStream()){
            byte[] buffer=new byte[8192];int count;while((count=input.read(buffer))!=-1)if(count>0)output.write(buffer,0,count);
            return Map.of("text",new String(output.toByteArray(),StandardCharsets.UTF_8));}
    }
    private Map<String,?> sources() {
        List<Map<String,Object>> items=new ArrayList<>();
        for(var source:app.catalogRuntime().productSourcesSnapshot()) {
            var row=source.source();boolean builtin=row.type()==RomSource.Type.BUILTIN;
            String uuid=source.uuid();var op=app.catalogRuntime().scanOperations().snapshot(source.id());
            Map<String,Object> item=new LinkedHashMap<>();item.put("uuid",uuid);item.put("name",builtin?"Built-in games":sourceNames.get(uuid,row.uri()));
            item.put("type",builtin?"builtin":android.provider.DocumentsContract.isTreeUri(Uri.parse(row.uri()))?"folder":"file");
            String phase=op==null?(row.isUsable()?"completed":"failed"):op.phase();
            item.put("count",source.count());item.put("status",phase);
            item.put("reason",op==null?(row.isUsable()?"":"source_unavailable"):op.reason());item.put("builtin",builtin);item.put("canReauthorize",!builtin&&!row.isUsable());
            item.put("canCancel",op!=null&&op.canCancel());item.put("operationId",op==null?"":op.operationId());item.put("phase",phase);item.put("completed",op==null?0:op.completed());
            if(op!=null&&op.total()!=null)item.put("total",op.total());items.add(item);
        }return Map.of("items",items);
    }
    private String sourceId(String uuid){
        for(var source:app.catalogRuntime().productSourcesSnapshot())if(source.uuid().equals(uuid))return source.id();
        throw new Failure("source_unavailable");
    }
    private String sourceName(String locator) {
        try {Uri uri=Uri.parse(locator);Uri doc=android.provider.DocumentsContract.isTreeUri(uri)?android.provider.DocumentsContract.buildDocumentUriUsingTree(uri,android.provider.DocumentsContract.getTreeDocumentId(uri)):uri;
            try(var cursor=app.getContentResolver().query(doc,new String[]{android.provider.OpenableColumns.DISPLAY_NAME},null,null,null)) {
                if(cursor!=null&&cursor.moveToFirst())return cursor.getString(0);
            }
        }catch(RuntimeException ignored){}return null;
    }
    private void pickSource(MethodCall call,Request request) {
        String kind=string(call,"kind");
        if(!Set.of("file","folder").contains(kind))throw new IllegalArgumentException();
        Intent intent=new Intent(kind.equals("folder")?Intent.ACTION_OPEN_DOCUMENT_TREE:Intent.ACTION_OPEN_DOCUMENT);
        if(kind.equals("file"))intent.setType("*/*").addCategory(Intent.CATEGORY_OPENABLE);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        FlutterFoundationActivity owner=requireHost();ProductPicker.Pending<PickerRequest> pending;
        try{pending=picker.begin(owner.productHostIdentity(),new PickerRequest(request,optional(call,"sourceUuid")));}
        catch(IllegalStateException busy){throw new Failure("native_busy");}
        try{owner.startActivityForResult(intent,pending.requestCode());}catch(RuntimeException failure){picker.take(pending.owner(),pending.requestCode());throw failure;}
    }
    void pickerReturned(FlutterFoundationActivity owner,int code,int result,Intent data) {
        PickerRequest pending=picker.take(owner.productHostIdentity(),code);if(pending==null)return;
        Request request=pending.request();String uuid=pending.uuid();
        if(result!=Activity.RESULT_OK||data==null||data.getData()==null){request.success(Map.of("status","cancelled","operationId",""));return;}
        sourceWork(request,()->{var source=app.catalogRuntime().addOrReauthorizeProductSource(data.getData().toString(),data.getFlags(),uuid).get();
            String assigned=app.catalogRuntime().productSourceUuid(source.id());sourceNames.refresh(assigned,source.uri());String operation=startScan(assigned);
            return Map.of("status","started","operationId",operation);});
    }
    private void scanSource(String uuid,Request request) {
        request.success(Map.of("status","started","operationId",startScan(uuid)));
    }
    private void sourceWork(Request request,Callable<Map<String,?>> action){sourceWorker.execute(()->{
        try{app.catalogRuntime().nativeReady().get();request.success(action.call());}
        catch(Exception failure){request.error(errorCode(failure));}
    });}
    private String startScan(String uuid) {
        if("builtin".equals(uuid))throw new Failure("source_protected");
        try{return app.catalogRuntime().startSourceScan(sourceId(uuid)).operationId();}
        catch(IllegalStateException busy){throw new Failure("native_busy");}
    }
    private void launch(MethodCall call,Request request) {
        String id=string(call,"canonicalId");String purpose=string(call,"purpose");requireHost();
        FlutterFoundationActivity owner=requireHost();
        if(pendingRoutes.containsKey(owner))throw new Failure("native_busy");pendingRoutes.put(owner,request);
        if("nearby".equals(purpose)) {
            NearbyMvpSession original=nearbyOwner.session();
            if(original==null){pendingRoutes.remove(owner,request);request.error("nearby_unavailable");return;}
            var port=nearbyPorts.create(id,original,()->{
                pendingRoutes.remove(owner,request);
                request.result.success(ProductEnvelope.reply(request.id,request.lease,instance,Map.of("status","returned")));
                owner.finish();
            });
            worker.execute(()->{try {
                ProductNearbySelection.run(port,
                        action->request.nearbyCommands.run(nearbyOwner,()->nearbyOwner.session()==original,action),
                        action->completeNearbyOnMain(owner,request,original,action),
                        android.os.SystemClock::elapsedRealtime,()->Thread.sleep(10));
            }catch(Exception error){main.post(()->{pendingRoutes.remove(owner,request);request.error(errorCode(error));});}});return;
        }
        if(!"single".equals(purpose)){pendingRoutes.remove(owner);throw new IllegalArgumentException();}
        app.gameLaunchService().launchCanonical(id,launch->{
            if(pendingRoutes.get(owner)!=request||host!=owner||!launch.sessionCommitted()) {
                launch.request().ifPresent(PendingGameLaunch::discard);pendingRoutes.remove(owner);request.success(Map.of("status","unavailable","reason","launch_unavailable"));return;
            }
            try {host.startActivityForResult(new Intent(host,MainActivity.class).putExtra(FoundationBridge.RETURN_TO_FOUNDATION,true),ROUTE);}
            catch(RuntimeException failure){launch.request().ifPresent(PendingGameLaunch::discard);pendingRoutes.remove(owner);request.error("launch_unavailable");}
        });
    }
    private void invalidateNearby(FlutterFoundationActivity activity) {
        Request request=pendingRoutes.get(activity);
        if(request!=null)request.nearbyCommands.invalidate();
    }
    private void completeNearbyOnMain(FlutterFoundationActivity owner,Request request,NearbyMvpSession original,
            ProductNearbySelection.Action action) throws Exception {
        CompletableFuture<Void> checked=new CompletableFuture<>();
        // Only UI completion crosses to main. All native commands have already finished on the
        // worker; this final check prevents a stale request from finishing a replacement host.
        main.post(()->{try {
            if(host!=owner||generation!=request.lease||owner.isFinishing()||pendingRoutes.get(owner)!=request)
                throw new ProductNearbySelection.Failure("stale_host");
            request.nearbyCommands.run(nearbyOwner,()->nearbyOwner.session()==original,action);
            checked.complete(null);
        }catch(Exception failure){checked.completeExceptionally(failure);}});
        checked.get();
    }
    private ProductNearbySelection.Port nearbyPort(String id,NearbyMvpSession original,Runnable complete) {
        return new ProductNearbySelection.Port() {
            public void ready() throws Exception {app.catalogRuntime().nativeReady().get();}
            public ProductNearbySelection.Selection load() throws Exception {return loadNearbySelection(id);}
            public int state(){return original.snapshot()[0];}
            public boolean returnLobby(){return original.returnLobby();}
            public boolean select(ProductNearbySelection.Selection selection){return original.selectGame(selection.bytes(),selection.key());}
            public boolean confirm(){return original.confirm();}
            public void publish(ProductNearbySelection.Selection selection){nearbyOwner.gameTitle(selection.title());nearbyOwner.gameKey(selection.key());}
            public void complete(){complete.run();}
        };
    }
    private ProductNearbySelection.Selection loadNearbySelection(String id)throws Exception {
        com.flynes.emu.catalog.GameVariant selected=null;
        for(var entry:app.catalogRuntime().gameCatalog().canonicalEntries())if(entry.canonicalGame().id().equals(id))
            for(var variant:entry.variants())if(variant.isLaunchable()){selected=variant;break;}
        if(selected==null)throw new Failure("launch_unavailable");
        var row=GameCenterSnapshot.findRow(app.catalogRuntime().gameCenterSnapshot().rows(),id);
        if(row==null||!Boolean.TRUE.equals(item(id,app.catalogRuntime().gameCenterSnapshot()).get("multiplayerSupported")))throw new Failure("multiplayer_unsupported");
        var content=app.catalogRuntime().nearbyContentLoader().load(selected.variantId());
        var builtin=builtinFacts(app.catalogRuntime().gameCenterSnapshot()).get(id);
        String key=builtin==null?id:builtin.canonicalId;
        return new ProductNearbySelection.Selection(content.bytes(),key,row.titleEn());
    }
    private void openNative(MethodCall call,Request request) {
        String page=string(call,"page");Class<?> target=switch(page){case "layout"->ControlLayoutActivity.class;case "nearby"->NearbyFriendsActivity.class;default->throw new IllegalArgumentException();};
        FlutterFoundationActivity owner=requireHost();
        if(pendingRoutes.containsKey(owner))throw new Failure("native_busy");pendingRoutes.put(owner,request);
        try{owner.startActivityForResult(new Intent(owner,target),ROUTE);}catch(RuntimeException failure){pendingRoutes.remove(owner);throw failure;}
    }
    private FlutterFoundationActivity requireHost(){if(host==null||host.isFinishing())throw new Failure("host_unavailable");return host;}
    private void changed(String... domains){long ticket=observation.ticket();long lease=generation;
        if(!observation.accepts(ticket))return;
        main.post(()->{if(observation.accepts(ticket))channel.invokeMethod("projectionChanged",ProductEnvelope.reply(0,lease,instance,
            Map.of("domains",List.of(domains),"catalogGeneration",app.catalogRuntime().gameCenterSnapshot().nativeGeneration())));});}
    private static String string(MethodCall call,String key){Object value=call.argument(key);if(!(value instanceof String s)||s.isEmpty())throw new IllegalArgumentException();return s;}
    private static String optional(MethodCall call,String key){Object value=call.argument(key);if(value==null)return "";if(!(value instanceof String s))throw new IllegalArgumentException();return s;}
    private static boolean bool(MethodCall call,String key){Object value=call.argument(key);if(!(value instanceof Boolean b))throw new IllegalArgumentException();return b;}
    private static long number(MethodCall call,String key){Object value=call.argument(key);if(!(value instanceof Number n))throw new IllegalArgumentException();return n.longValue();}
}
