package com.flynes.emu;

import com.flynes.emu.settings.AppSettings;
import org.junit.Test;
import static org.junit.Assert.*;

public class ProductSettingsTest {
    @Test public void rejectsIntegralDoublesBeforeCapabilityKeyLookup() {
        assertThrows(IllegalArgumentException.class, () -> ProductSettings.patch(
                AppSettings.defaults(), "videoQualityPreset", 3.0));
        assertThrows(IllegalArgumentException.class, () -> ProductSettings.patch(
                AppSettings.defaults(), "customTemporalMode", 2.0));
    }

    @Test public void failedProductPatchIsNeverRetriedOrProjectedAsCommitted() {
        class Backend implements com.flynes.emu.settings.NativeSettingsStore.Backend {
            com.flynes.emu.settings.FlySettingsSnapshot persisted =
                    com.flynes.emu.settings.FlySettingsMapper.toNative(AppSettings.defaults());
            boolean fail = true;
            int writes;
            public com.flynes.emu.settings.FlySettingsSnapshot get() { return persisted; }
            public boolean apply(com.flynes.emu.settings.FlySettingsSnapshot value) {
                writes++;
                if (fail) return false;
                persisted = value;
                return true;
            }
        }
        Backend backend = new Backend();
        var repository = new com.flynes.emu.settings.SettingsRepository(
                new com.flynes.emu.settings.NativeSettingsStore(backend));
        assertFalse(ProductSettings.save(repository, "audioEnabled", false));
        assertTrue("Rejected values must not appear in the product projection",
                ProductSettings.read(repository).audioEnabled());
        backend.fail = false;
        assertTrue("Legacy consumers must not retry a failed product patch", repository.load().audioEnabled());
        assertEquals("Reading may not retry the rejected write", 1, backend.writes);
        assertTrue(ProductSettings.save(repository, "directionMode", 3));
        assertTrue(ProductSettings.read(repository).audioEnabled());
        assertEquals(3, ProductSettings.values(ProductSettings.read(repository)).get("directionMode"));
    }
    @Test public void patchesOnlyRequestedFieldAndUsesPublicEnums() {
        AppSettings initial = AppSettings.defaults().toBuilder().lastPlayedRomId("existing")
                .buttonScale(1.2f).audioEnabled(false).build();
        AppSettings patched = ProductSettings.patch(initial, "directionMode", 3);
        assertEquals(3, ProductSettings.values(patched).get("directionMode"));
        assertFalse(patched.audioEnabled());
        assertEquals("existing", patched.lastPlayedRomId());
        assertEquals(1.2f, patched.buttonScale(), 0f);
        assertEquals(false, ProductSettings.values(patched).get("audioEnabled"));
    }
    @Test public void rejectsUnknownFieldsAndWrongValueTypes() {
        assertThrows(IllegalArgumentException.class, () -> ProductSettings.patch(AppSettings.defaults(), "lastPlayedId", "bad"));
        assertThrows(IllegalArgumentException.class, () -> ProductSettings.patch(AppSettings.defaults(), "audioEnabled", 1));
        assertThrows(IllegalArgumentException.class, () -> ProductSettings.patch(AppSettings.defaults(), "aspectMode", 99));
    }
}
