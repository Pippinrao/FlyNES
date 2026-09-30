package com.flynes.emu;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;

/** Product Flutter host, borrowing the one process engine with an exclusive view lease. */
public final class FlutterFoundationActivity extends FlutterActivity {
    private final String presentationToken=java.util.UUID.randomUUID().toString();
    private final ProductPresentationGate presentation=new ProductPresentationGate(presentationToken);
    private android.view.ViewTreeObserver.OnPreDrawListener presentationListener;
    String presentationToken(){return presentationToken;}
    boolean presentationReady(String token,long frame) {
        if(leaseReleased||isFinishing()||!presentation.acknowledge(token,frame))return false;
        getWindow().getDecorView().invalidate();
        return true;
    }
    @Override public io.flutter.embedding.android.RenderMode getRenderMode() {
        return io.flutter.embedding.android.RenderMode.surface;
    }
    private String productHostIdentity;
    String productHostIdentity(){return productHostIdentity;}
    private boolean leaseReleased;
    void releaseEngineLease() {
        if(leaseReleased)return;
        leaseReleased=true;
        detachFromFlutterEngine();
    }
    private com.flynes.emu.flutter.FoundationTextureProbe textureProbe;
    private boolean isTextureProbe() {
        return BuildConfig.DEBUG && getIntent().getBooleanExtra("flutter_texture_probe", false);
    }
    @Override public FlutterEngine provideFlutterEngine(Context context) {
        if (isTextureProbe()) {
            FlutterEngine engine = new FlutterEngine(context);
            textureProbe = new com.flynes.emu.flutter.FoundationTextureProbe(context, engine);
            var loader = io.flutter.FlutterInjector.instance().flutterLoader();
            engine.getDartExecutor().executeDartEntrypoint(
                    new io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint(
                            loader.findAppBundlePath(), "textureProbeMain"));
            return engine;
        }
        FlyNesApplication app=(FlyNesApplication)getApplication();
        app.acquireFlutterHost(this);
        return app.foundationEngine();
    }
    @Override public boolean shouldDestroyEngineWithHost() { return isTextureProbe(); }
    @Override protected void onCreate(Bundle state) {
        productHostIdentity=state==null?java.util.UUID.randomUUID().toString():state.getString("product_host_identity",java.util.UUID.randomUUID().toString());
        super.onCreate(state);
        if (!isTextureProbe()) {
            // Surface rendering proceeds while Android's first draw is held. This
            // would deadlock Texture mode, so this host explicitly uses Surface.
            presentationListener=()->{
                if(!presentation.ready())return false;
                getWindow().getDecorView().getViewTreeObserver().removeOnPreDrawListener(presentationListener);
                getWindow().getDecorView().post(()->((FlyNesApplication)getApplication()).flutterPresented(this));
                return true;
            };
            getWindow().getDecorView().getViewTreeObserver().addOnPreDrawListener(presentationListener);
            ((FlyNesApplication) getApplication()).foundationBridge().attach(this);
            ((FlyNesApplication) getApplication()).productBridge().attach(this);
        }
    }
    @Override protected void onRestart() {
        super.onRestart();
        if(leaseReleased)recreate();
    }
    @Override protected void onResume() {
        super.onResume();
        if (textureProbe != null) textureProbe.setActive(true);
        if(!isTextureProbe()&&!leaseReleased)((FlyNesApplication)getApplication()).productBridge().resume(this);
    }
    @Override protected void onPause() {
        if(!isTextureProbe())((FlyNesApplication)getApplication()).productBridge().suspend(this);
        if (textureProbe != null) textureProbe.setActive(false);
        super.onPause();
    }
    @Override protected void onDestroy() {
        if(presentationListener!=null&&getWindow().getDecorView().getViewTreeObserver().isAlive())
            getWindow().getDecorView().getViewTreeObserver().removeOnPreDrawListener(presentationListener);
        if (textureProbe != null) textureProbe.close();
        if (!isTextureProbe()) {
            FlyNesApplication app=(FlyNesApplication)getApplication();
            app.foundationBridge().detach(this);app.productBridge().detach(this);app.releaseFlutterHost(this);
        }
        super.onDestroy();
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == FoundationBridge.NATIVE_ROUTE)
            ((FlyNesApplication) getApplication()).foundationBridge().returned(this);
        if(request==ProductBridge.ROUTE)((FlyNesApplication)getApplication()).productBridge().returned(this);
        if(!isTextureProbe())((FlyNesApplication)getApplication()).productBridge().pickerReturned(this,request,result,data);
    }
    @Override protected void onSaveInstanceState(Bundle state){state.putString("product_host_identity",productHostIdentity);super.onSaveInstanceState(state);}
}
