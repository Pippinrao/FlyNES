package com.flynes.emu;

import com.flynes.emu.catalog.GameVariant;
import com.flynes.emu.data.RomIdentity;
import com.flynes.emu.save.HistoryStore;
import com.flynes.emu.save.SaveRecord;
import com.flynes.emu.save.SaveRepository;
import java.io.File;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Shared read-only resume projection for the native and Flutter halls. Call on an IO worker. */
final class AndroidResumeService {
    private final FlyNesApplication app;
    private final Map<String, RomIdentity> identities = new ConcurrentHashMap<>();
    AndroidResumeService(FlyNesApplication app) { this.app = app; }

    Map<String, String> query(String canonicalId) throws Exception {
        app.catalogRuntime().nativeReady().get();
        GameVariant selected = null;
        for (var entry : app.catalogRuntime().gameCatalog().canonicalEntries()) {
            if (!entry.canonicalGame().id().equals(canonicalId)) continue;
            for (var variant : entry.variants()) if (variant.isLaunchable()) { selected = variant; break; }
            break;
        }
        if (selected == null) return Map.of("state", "unavailable", "reason", "Game source unavailable");
        RomIdentity identity = identity(selected);
        File database = new File(app.getFilesDir(), "save-history.sqlite");
        return FoundationResumeQuery.read(() -> {
            if (!database.isFile()) return null;
            try (HistoryStore store = new HistoryStore(database)) {
                long head = store.head(identity.sha1());
                return head == 0 ? null : store.read(identity.sha1(), head, false);
            }
        }, () -> new SaveRepository(app).readAutosave(identity).map(SaveRecord::state).orElse(null));
    }

    private synchronized RomIdentity identity(GameVariant variant) throws Exception {
        // Catalog SHA-1 covers the ROM file. Existing history uses the core's PRG/CHR SHA-1.
        String payload = variant.hashes().payloadSha256();
        RomIdentity cached = identities.get(payload);
        if (cached != null) return cached;
        byte[] bytes = app.catalogRuntime().nearbyContentLoader().load(variant.variantId()).bytes();
        NesCore probe = new NesCore();
        try {
            if (!probe.create() || probe.loadRom(bytes) < 0)
                throw new IllegalStateException("Game identity unavailable");
            RomIdentity identity = probe.romInfo().identity();
            identities.put(payload, identity);
            return identity;
        } finally { probe.destroy(); }
    }
}
