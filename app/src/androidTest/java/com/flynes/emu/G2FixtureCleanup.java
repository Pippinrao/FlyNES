package com.flynes.emu;
/** Test-owned restoration: every independent step must run even after another fails. */
final class G2FixtureCleanup {
    interface Step { void run() throws Throwable; }
    static Throwable all(Step... steps) {
        Throwable first=null;
        for(Step step:steps)try {step.run();}
        catch(Throwable failure){if(first==null)first=failure;else first.addSuppressed(failure);}
        return first;
    }
}
