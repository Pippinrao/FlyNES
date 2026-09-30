package com.flynes.emu;
import static org.junit.Assert.*;
import org.junit.Test;
public class ProductHostObservationTest {
    @Test public void queuedEventCannotAcquireANewerHostGeneration() {
        var observation=new ProductHostObservation<Object>();Object first=new Object(),next=new Object();
        observation.attach(first);long ticket=observation.ticket();
        observation.attach(next);assertFalse(observation.accepts(ticket));
        observation.detach(first);assertTrue(observation.accepts(observation.ticket()));
    }
    @Test public void explicitDetachStaysDetachedAcrossResumeUntilBootstrap() {
        var observation=new ProductHostObservation<Object>();Object host=new Object();observation.attach(host);
        long before=observation.ticket();observation.suspend(host);assertFalse(observation.accepts(before));
        observation.resume(host);assertTrue(observation.accepts(observation.ticket()));
        observation.unsubscribe();observation.resume(host);assertFalse(observation.accepts(observation.ticket()));
        observation.subscribe();assertTrue(observation.accepts(observation.ticket()));
    }
    @Test public void obsoletePickerCannotConsumeNewRequestButRecreatedOwnerCanReturn() {
        var picker=new ProductPicker<String>();var first=picker.begin("logical-host","one");
        assertNull(picker.take("other-host",first.requestCode()));
        assertEquals("one",picker.take("logical-host",first.requestCode()));
        var next=picker.begin("logical-host","two");
        assertNull(picker.take("logical-host",first.requestCode()));
        assertEquals("two",picker.take("logical-host",next.requestCode()));
    }
}
