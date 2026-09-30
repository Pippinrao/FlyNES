package com.flynes.emu.save;

import java.util.function.Consumer;

/** Synchronous AUTO operation; fallback recovery and post-capture resume share one action. */
public final class AutomaticSaveCycle {
    private AutomaticSaveCycle(){}
    public static void run(Consumer<Runnable> save,Runnable resume){
        var attempted=new java.util.concurrent.atomic.AtomicBoolean();
        Runnable once=()->{if(attempted.compareAndSet(false,true))resume.run();};
        try{save.accept(once);}finally{once.run();}
    }
}
