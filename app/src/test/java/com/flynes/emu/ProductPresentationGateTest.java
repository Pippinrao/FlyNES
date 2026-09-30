package com.flynes.emu;
import static org.junit.Assert.*;
import org.junit.Test;
public class ProductPresentationGateTest {
    @Test public void staleRasterAckCannotRevealReplacementHost() {
        var replacement=new ProductPresentationGate("replacement");
        assertFalse(replacement.acknowledge("old-host",42));assertFalse(replacement.ready());
        assertFalse(replacement.acknowledge("replacement",0));assertFalse(replacement.ready());
        assertTrue(replacement.acknowledge("replacement",43));assertTrue(replacement.ready());
    }
}
