package com.flynes.emu.save;

import static org.junit.Assert.*;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;

public class AutomaticSaveCycleTest {
    @Test public void resumeRunsBetweenCaptureAndStoreExactlyOnce(){
        var events=new ArrayList<String>();
        AutomaticSaveCycle.run(resume->{events.add("capture");resume.run();events.add("store");},()->events.add("resume"));
        assertEquals(List.of("capture","resume","store"),events);
    }
    @Test public void captureAndStoreFailuresEachRecoverOnceAndKeepTheFailure(){
        for(boolean afterCapture:new boolean[]{false,true}){
            AtomicInteger resumes=new AtomicInteger();
            RuntimeException failure=new IllegalStateException("save failed");
            try{
                AutomaticSaveCycle.run(resume->{if(afterCapture)resume.run();throw failure;},resumes::incrementAndGet);
                fail("Failure must propagate");
            }catch(RuntimeException actual){assertSame(failure,actual);}
            assertEquals("No duplicate audio owner on failed store",1,resumes.get());
        }
    }
    @Test public void skippedSaveAndFailedResumeCannotCreateAnotherOwner(){
        AtomicInteger resumes=new AtomicInteger();
        AutomaticSaveCycle.run(ignored->{},resumes::incrementAndGet);
        assertEquals(1,resumes.get());
        RuntimeException failure=new IllegalStateException("resume failed");
        resumes.set(0);
        try{
            AutomaticSaveCycle.run(resume->{resume.run();fail("Store must not start after failed resume");},()->{
                resumes.incrementAndGet();throw failure;
            });
            fail();
        }catch(RuntimeException actual){assertSame(failure,actual);}
        assertEquals(1,resumes.get());
    }
}
