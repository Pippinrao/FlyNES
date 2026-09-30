package com.flynes.emu;
import org.junit.Test;
import java.util.Map;
import static org.junit.Assert.*;
public class ProductEnvelopeTest {
    @Test public void rejectsStaleHostExceptUnknownBootstrap() {
        assertFalse(ProductEnvelope.accepts(1,2,false));
        assertFalse(ProductEnvelope.accepts(1,2,true));
        assertTrue(ProductEnvelope.accepts(0,2,true));
        assertTrue(ProductEnvelope.accepts(2,2,false));
    }
    @Test public void attachesAuthoritativeEnvelope() {
        Map<String,Object> value=ProductEnvelope.reply(9,2,"instance",Map.of("status","completed","hostGeneration",99));
        assertEquals(9,value.get("requestId")); assertEquals(2L,value.get("hostGeneration"));
        assertEquals("instance",value.get("instanceId")); assertEquals("completed",value.get("status"));
    }
}
