package com.flynes.emu;

import android.view.accessibility.AccessibilityNodeInfo;
import android.graphics.Rect;
import android.os.SystemClock;
import androidx.test.platform.app.InstrumentationRegistry;
import static org.junit.Assert.*;

/** Current product accessibility, without channel shortcuts or G1 widget identifiers. */
final class G2PerformanceUi {
    static boolean enginePresent(FlyNesApplication app) throws Exception {
        var field=FlyNesApplication.class.getDeclaredField("foundationEngine"); field.setAccessible(true);
        return field.get(app)!=null;
    }
    static boolean visible(AccessibilityNodeInfo node) {
        if(node==null)return false;
        Rect bounds=new Rect();node.getBoundsInScreen(bounds);
        return node.isVisibleToUser()&&!bounds.isEmpty();
    }
    static boolean primary(AccessibilityNodeInfo node) {
        if(!visible(node)||!node.isEnabled()||!node.isClickable())return false;
        String label=String.valueOf(node.getContentDescription());
        String text=String.valueOf(node.getText());
        for(String expected:new String[]{"Start","开始","Continue","继续"})
            if(expected.equals(label)||expected.equals(text))return true;
        return false;
    }
    static boolean card(AccessibilityNodeInfo node) {
        return G2CardObservation.card(facts(node));
    }
    private static G2CardObservation.Node facts(AccessibilityNodeInfo node) {
        if(node==null)return null;
        Rect bounds=new Rect();node.getBoundsInScreen(bounds);
        var children=new java.util.ArrayList<G2CardObservation.Node>();
        for(int i=0;i<node.getChildCount();i++){
            var child=node.getChild(i);
            if(child!=null){children.add(facts(child));child.recycle();}
        }
        var label=node.getContentDescription();
        return new G2CardObservation.Node(String.valueOf(node.getClassName()),label==null?null:label.toString(),
                visible(node),node.isClickable(),bounds.left,bounds.top,bounds.right,bounds.bottom,children);
    }
    static AccessibilityNodeInfo find(AccessibilityNodeInfo node,java.util.function.Predicate<AccessibilityNodeInfo> predicate) {
        if(node==null)return null;if(predicate.test(node))return node;
        for(int i=0;i<node.getChildCount();i++){var found=find(node.getChild(i),predicate);if(found!=null)return found;}
        return null;
    }
    static void clickPrimary() {
        long deadline=SystemClock.elapsedRealtime()+30000;
        do {
            var node=find(InstrumentationRegistry.getInstrumentation().getUiAutomation().getRootInActiveWindow(),G2PerformanceUi::primary);
            if(node!=null){assertTrue(node.performAction(AccessibilityNodeInfo.ACTION_CLICK));return;}
            SystemClock.sleep(25);
        }while(SystemClock.elapsedRealtime()<deadline);
        fail("G2 visible enabled Start/Continue was not observed");
    }
    static org.json.JSONObject memory() throws Exception {
        var info=new android.os.Debug.MemoryInfo();android.os.Debug.getMemoryInfo(info);
        return new org.json.JSONObject().put("pssKb",info.getTotalPss())
                .put("javaUsedBytes",Runtime.getRuntime().totalMemory()-Runtime.getRuntime().freeMemory())
                .put("nativeHeapBytes",android.os.Debug.getNativeHeapAllocatedSize());
    }
    static java.util.Map<String,?> select(android.content.Context context,String canonicalId) {
        assertFalse("Explicit canonical content is required",canonicalId.isEmpty());
        var preferences=context.getSharedPreferences("game_center_ui",0);
        var original=new java.util.HashMap<>(preferences.getAll());
        assertTrue(preferences.edit().putString("category","ALL").putString("query","")
                .putBoolean("multiplayerOnly",false).putString("selected",canonicalId)
                .putString("product.selected.all",canonicalId).commit());
        return original;
    }
    static boolean restore(android.content.Context context,java.util.Map<String,?> original) {
        var prefs=context.getSharedPreferences("game_center_ui",0);var edit=prefs.edit().clear();
        for(var entry:original.entrySet()){
            Object value=entry.getValue();String key=entry.getKey();
            if(value instanceof String)edit.putString(key,(String)value);
            else if(value instanceof Boolean)edit.putBoolean(key,(Boolean)value);
            else if(value instanceof Integer)edit.putInt(key,(Integer)value);
            else if(value instanceof Long)edit.putLong(key,(Long)value);
            else if(value instanceof Float)edit.putFloat(key,(Float)value);
            else if(value instanceof java.util.Set){@SuppressWarnings("unchecked") var set=(java.util.Set<String>)value;edit.putStringSet(key,set);}
        }
        return edit.commit()&&original.equals(prefs.getAll());
    }
    static long gcCount(){
        String value=android.os.Debug.getRuntimeStat("art.gc.gc-count");
        return value==null?-1:Long.parseLong(value);
    }
    static org.json.JSONObject afterGc(int cycle) throws Exception {
        long before=gcCount(); assertTrue("ART GC completion counter must be available",before>=0);
        var weak=new java.lang.ref.WeakReference<>(new Object());
        long began=SystemClock.elapsedRealtime(),deadline=began+5000;
        do {System.gc();System.runFinalization();SystemClock.sleep(25);}
        while((gcCount()<=before||weak.get()!=null)&&SystemClock.elapsedRealtime()<deadline);
        long after=gcCount();assertTrue("GC request alone is not evidence",after>before);
        assertNull("Marker proves collection completed",weak.get());
        return memory().put("cycle",cycle).put("gcBefore",before).put("gcAfter",after)
                .put("weakMarkerCleared",true).put("gcWaitMs",SystemClock.elapsedRealtime()-began)
                .put("dartHeap",new org.json.JSONObject().put("status","unavailable").put("reason","Release VM service disabled"));
    }
}
