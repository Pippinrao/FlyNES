package com.flynes.emu;

import static org.junit.Assert.*;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import com.flynes.emu.catalog.BuiltinGames;
import org.junit.Test;
import org.junit.runner.RunWith;

/** A stop made before the worker is scheduled must never start emulation. */
@RunWith(AndroidJUnit4.class)
public class AudioThreadLifecycleIntegrationTest {
    @Test public void stopBeforeStartRemainsStopped() throws Exception {
        var context = ApplicationProvider.getApplicationContext();
        NesCore core = new NesCore();
        assertTrue(core.create());
        AudioThread audio = new AudioThread(core);
        try {
            BuiltinGames games;
            try (var in = context.getAssets().open(BuiltinGames.ASSET_NAME)) {
                games = BuiltinGames.parse(in);
            }
            try (var in = context.getAssets().open(games.all().get(0).assetPath())) {
                assertTrue(core.loadRom(in.readAllBytes()) >= 0);
            }
            core.setAudioFormat(48000, 0);
            byte[] before = core.saveState();
            audio.stopLoop();
            audio.start();
            audio.join(1000);
            assertFalse("A pre-start stop must survive run(); no audio loop may start", audio.isAlive());
            assertArrayEquals("A cancelled worker must not step the core", before, core.saveState());
        } finally {
            audio.stopLoop();
            audio.join(5000);
            if (!audio.isAlive()) core.destroy();
        }
    }
}
