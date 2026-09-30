package com.flynes.emu;
public final class G2FixtureCleanupTest {
    public static void main(String[] ignored) {
        var calls=new java.util.ArrayList<String>();
        Throwable failed=G2FixtureCleanup.all(()->{calls.add("hosts");throw new IllegalStateException("hosts");},
            ()->{calls.add("head");throw new AssertionError("head");},()->calls.add("cover"),
            ()->{calls.add("settings");throw new IllegalStateException("settings");},()->calls.add("navigation"),()->calls.add("report"));
        if(!calls.equals(java.util.List.of("hosts","head","cover","settings","navigation","report")))throw new AssertionError("Every restore and report must be attempted: "+calls);
        if(failed==null||failed.getSuppressed().length!=2)throw new AssertionError("Preserve all restoration failures");
        if(G2FixtureCleanup.all(()->{})!=null)throw new AssertionError("Successful cleanup");
        System.out.println("PASS all independent restorations/report despite host/head/settings failures; failures retained");
    }
}
