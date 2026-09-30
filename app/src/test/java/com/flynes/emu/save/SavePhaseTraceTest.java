package com.flynes.emu.save;

import static org.junit.Assert.*;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;

public class SavePhaseTraceTest {
    @Test public void recordsSynchronousBoundariesWithoutChangingValueOrThread() throws Exception {
        var events=new ArrayList<SavePhaseTrace.Event>();
        long thread=Thread.currentThread().getId();
        try(var ignored=SavePhaseTrace.observe(events::add)){
            assertEquals("stored",SavePhaseTrace.measure("store",()->{
                assertEquals(thread,Thread.currentThread().getId());return "stored";
            }));
        }
        assertEquals(List.of("store.begin","store.end"),events.stream().map(SavePhaseTrace.Event::phase).toList());
        assertTrue(events.get(1).monotonicNs()>=events.get(0).monotonicNs());
        assertTrue(events.stream().allMatch(event->event.threadId()==thread));
        SavePhaseTrace.measure("disabled",()->true);assertEquals(2,events.size());
    }
    @Test public void preservesBusinessFailureAndIgnoresDiagnosticFailure() throws Exception {
        var events=new ArrayList<SavePhaseTrace.Event>();
        var actual=new IllegalStateException("store failed");
        try(var ignored=SavePhaseTrace.observe(events::add)){
            try{SavePhaseTrace.measure("store",()->{throw actual;});fail();}
            catch(IllegalStateException got){assertSame(actual,got);}
        }
        assertEquals(List.of("store.begin","store.failed"),events.stream().map(SavePhaseTrace.Event::phase).toList());
        AtomicInteger calls=new AtomicInteger();
        try(var ignored=SavePhaseTrace.observe(event->{throw new IllegalStateException("diagnostic only");})){
            assertEquals(Integer.valueOf(1),SavePhaseTrace.measure("store",calls::incrementAndGet));
        }
        assertEquals(1,calls.get());
    }
}
