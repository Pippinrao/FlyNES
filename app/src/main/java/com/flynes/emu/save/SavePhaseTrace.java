package com.flynes.emu.save;

import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;
import java.util.function.Supplier;

/** Opt-in software diagnostics. Disabled normally; never owns or schedules save work. */
public final class SavePhaseTrace {
    public record Event(String phase,long monotonicNs,long threadId) {}
    private static final AtomicReference<Consumer<Event>> observer=new AtomicReference<>();
    private SavePhaseTrace(){}
    public static AutoCloseable observe(Consumer<Event> sink){
        if(!observer.compareAndSet(null,sink))throw new IllegalStateException("Save observer already installed");
        return ()->observer.compareAndSet(sink,null);
    }
    public static void event(String phase){
        var sink=observer.get();
        if(sink!=null){
            try{sink.accept(new Event(phase,System.nanoTime(),Thread.currentThread().getId()));}
            catch(RuntimeException ignored){/* Diagnostic sinks cannot change save outcomes. */}
        }
    }
    public static <T> T measure(String phase,Supplier<T> work){
        if(observer.get()==null)return work.get();
        event(phase+".begin");
        try{
            T result=work.get();event(phase+".end");return result;
        }catch(RuntimeException|Error failure){event(phase+".failed");throw failure;}
    }
}
