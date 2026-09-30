package com.flynes.emu;
import static org.junit.Assert.*;
import org.junit.Test;
public class ProductRoutesTest {
    @Test public void controlledBaselineRequiresBothBuildOptInAndExplicitIntent() {
        assertFalse(ProductRoutes.baselineAllowed(false,false));
        assertFalse(ProductRoutes.baselineAllowed(false,true));
        assertFalse(ProductRoutes.baselineAllowed(true,false));
        assertTrue(ProductRoutes.baselineAllowed(true,true));
    }
}
