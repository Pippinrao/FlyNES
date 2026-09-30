package com.flynes.emu.catalog.android;
import org.junit.Test;
import static org.junit.Assert.*;
public class ProductRegrantLocatorTest {
    @Test public void regrantInvalidatesOnlyTheTargetSourceCachedDocuments() {
        var map=new AndroidPackageLocatorMap();byte[] first=new byte[16],second=new byte[16];first[0]=1;second[0]=2;
        map.put(first,"game.nes","content://old/document/a");map.put(second,"game.nes","content://other/document/b");
        map.invalidateSource(first);
        assertNull("Regrant must resolve against the new grant instead of a stale document",map.get(first,"game.nes"));
        assertEquals("content://other/document/b",map.get(second,"game.nes"));
    }
}
