package com.flynes.emu;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;

/** G1 validation route inside the existing product package. */
public final class FlutterFoundationActivity extends FlutterActivity {
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
        return ((FlyNesApplication) getApplication()).foundationEngine();
    }
    @Override public boolean shouldDestroyEngineWithHost() { return isTextureProbe(); }
    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        if (!isTextureProbe()) ((FlyNesApplication) getApplication()).foundationBridge().attach(this);
    }
    @Override protected void onResume() {
        super.onResume();
        if (textureProbe != null) textureProbe.setActive(true);
    }
    @Override protected void onPause() {
        if (textureProbe != null) textureProbe.setActive(false);
        super.onPause();
    }
    @Override protected void onDestroy() {
        if (textureProbe != null) textureProbe.close();
        if (!isTextureProbe()) ((FlyNesApplication) getApplication()).foundationBridge().detach(this);
        super.onDestroy();
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == FoundationBridge.NATIVE_ROUTE)
            ((FlyNesApplication) getApplication()).foundationBridge().returned(this);
    }
}
