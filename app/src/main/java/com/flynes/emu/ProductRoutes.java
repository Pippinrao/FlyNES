package com.flynes.emu;

import android.app.Activity;
import android.content.Intent;

/** Normal routes enter Flutter; baseline builds additionally require an explicit intent marker. */
public final class ProductRoutes {
    static final String NATIVE_BASELINE="controlled_native_baseline";
    static Intent intent(Activity activity,String route) {
        if(isNativeBaseline(activity))return nativeIntent(activity,switch(route){
            case "settings"->SettingsActivity.class;case "licenses"->LicensesActivity.class;default->HomeActivity.class;});
        return new Intent(activity,FlutterFoundationActivity.class).putExtra(ProductBridge.ROUTE_EXTRA,route);
    }
    static boolean baselineAllowed(boolean buildAllowed,boolean requested){return buildAllowed&&requested;}
    public static boolean isNativeBaseline(Activity activity){return baselineAllowed(BuildConfig.CONTROLLED_NATIVE_BASELINE,
            activity.getIntent().getBooleanExtra(NATIVE_BASELINE,false));}
    public static Intent nativeIntent(Activity owner,Class<?> destination){
        Intent next=new Intent(owner,destination);
        if(isNativeBaseline(owner))next.putExtra(NATIVE_BASELINE,true);
        return next;
    }
    static boolean redirect(Activity activity,String route) {
        if(isNativeBaseline(activity))return false;
        Intent intent=intent(activity,route);
        if(activity.getIntent().getBooleanExtra("nearby_choose_game",false))intent.putExtra(ProductBridge.PURPOSE_EXTRA,"nearby");
        intent.addFlags(Intent.FLAG_ACTIVITY_FORWARD_RESULT);
        activity.startActivity(intent);activity.finish();return true;
    }
}
