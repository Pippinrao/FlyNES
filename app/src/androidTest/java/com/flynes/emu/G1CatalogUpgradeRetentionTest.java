package com.flynes.emu;

import static org.junit.Assert.*;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.flynes.emu.settings.SettingsAccess;
import com.flynes.emu.settings.ControlLayoutRepository;
import com.flynes.emu.input.ControlLayoutV2;
import com.flynes.emu.launch.ExactRomLoader;
import com.flynes.emu.launch.LaunchRequest;
import java.io.File;
import java.nio.file.Files;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.concurrent.TimeUnit;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Opt-in production catalog/settings retention on the dedicated G1 upgrade AVD. */
@RunWith(AndroidJUnit4.class)
public class G1CatalogUpgradeRetentionTest {
    @Test public void preserveFavoriteSettingsLayoutAndGrantedSourceAcrossUpgrade() throws Exception {
        var args = InstrumentationRegistry.getArguments();
        String phase = args.getString("g1UpgradePhase", "");
        org.junit.Assume.assumeTrue("Explicit two-phase invocation only", phase.equals("seed") || phase.equals("verify"));
        String fixture = args.getString("g1UpgradeFixture", "");
        assertTrue(fixture.matches("[A-Za-z0-9_-]{8,80}"));
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        var runtime = app.catalogRuntime();
        runtime.bootstrap().get(30, TimeUnit.SECONDS);
        var settings = SettingsAccess.repository(app);
        var layout = new ControlLayoutRepository(app);
        File evidence = new File(app.getFilesDir(), "g1-catalog-upgrade-" + fixture + ".json");
        JSONObject expected;
        if (phase.equals("seed")) {
            assertFalse("Do not replace an existing fixture", evidence.exists());
            String tree = args.getString("sourceTree", "");
            assertFalse("A real OS picker grant is required", tree.isEmpty());
            assertTrue(app.getContentResolver().getPersistedUriPermissions().stream()
                    .anyMatch(grant -> grant.isReadPermission() && tree.equals(grant.getUri().toString())));
            var source = runtime.addOrReauthorizeTree(tree, 1).get(30, TimeUnit.SECONDS);
            runtime.scanSource(source.id()).get(30, TimeUnit.SECONDS);
            var game = runtime.gameCatalog().canonicalEntries().stream()
                    .filter(row -> row.variants().stream().anyMatch(v -> v.sourceId().equals(source.id())))
                    .findFirst().orElseThrow();
            var variant = game.variants().stream().filter(v -> v.sourceId().equals(source.id()))
                    .findFirst().orElseThrow();
            assertTrue(runtime.setFavorite(game.canonicalGame().id(), true).get(30, TimeUnit.SECONDS));
            assertTrue(settings.save(settings.load().toBuilder().buttonScale(1.17f)
                    .deadZone(.23f).localeTag("en").audioEnabled(false).build()));
            layout.save(layout.load().move(ControlLayoutV2.Element.A, .89f, .61f).withOpacity(.67f));
            expected = new JSONObject().put("canonicalId", game.canonicalGame().id())
                    .put("variantId", variant.variantId()).put("sourceId", source.id()).put("tree", tree)
                    .put("layout", layout.load().encode())
                    .put("payloadSha256", digest(new ExactRomLoader(runtime.streamOpener())
                            .load(LaunchRequest.forVariant(variant))));
            Files.write(evidence.toPath(), expected.toString().getBytes(StandardCharsets.UTF_8));
        } else {
            assertTrue("Seed must precede replacement", evidence.isFile());
            expected = new JSONObject(new String(Files.readAllBytes(evidence.toPath()), StandardCharsets.UTF_8));
        }
        assertEquals(1.17f, settings.load().buttonScale(), .0001f);
        assertEquals(.23f, settings.load().deadZone(), .0001f);
        assertEquals("en", settings.load().localeTag());
        assertFalse(settings.load().audioEnabled());
        assertEquals(expected.getString("layout"), layout.load().encode());
        String tree = expected.getString("tree");
        assertTrue("Replacement must preserve the OS read grant", app.getContentResolver()
                .getPersistedUriPermissions().stream().anyMatch(grant -> grant.isReadPermission()
                        && tree.equals(grant.getUri().toString())));
        var game = runtime.gameCatalog().canonicalEntries().stream()
                .filter(row -> row.canonicalGame().id().equals(expected.optString("canonicalId")))
                .findFirst().orElseThrow();
        assertTrue(game.favorite());
        var variant = game.variants().stream()
                .filter(v -> v.variantId().equals(expected.optString("variantId")))
                .findFirst().orElseThrow();
        assertEquals(expected.getString("sourceId"), variant.sourceId());
        assertEquals("Grant must still open the exact authorized content", expected.getString("payloadSha256"),
                digest(new ExactRomLoader(runtime.streamOpener()).load(LaunchRequest.forVariant(variant))));
    }
    private static String digest(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }
}
