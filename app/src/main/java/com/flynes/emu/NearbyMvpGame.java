package com.flynes.emu;

import android.content.Context;

import com.flynes.emu.catalog.BuiltinGames;
import com.flynes.emu.catalog.GameCatalogEntry;
import com.flynes.emu.catalog.GameVariant;
import com.flynes.emu.gamecenter.GameTitlePresentation;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;

/** Resolves the first manifest-declared two-player game without naming content in product code. */
final class NearbyMvpGame {
    static final class Selection {
        final BuiltinGames.Entry entry;
        final byte[] rom;
        final String title;
        Selection(BuiltinGames.Entry entry, byte[] rom) {
            this.entry = entry;
            this.rom = rom;
            this.title = java.util.Locale.getDefault().getLanguage().equals("zh")
                    ? entry.titleZhHans : entry.titleEn;
        }
        Selection(String title, byte[] rom) {
            this.entry = null;
            this.rom = rom;
            this.title = title;
        }
    }

    static Selection load(Context context) throws IOException {
        BuiltinGames games = BuiltinGames.fromAssets(context);
        for (BuiltinGames.Entry entry : games.all()) {
            if (entry.multiplayerEligibility != BuiltinGames.MultiplayerEligibility.SUPPORTED ||
                    entry.multiplayerMaxPlayers != 2) continue;
            return read(context, entry);
        }
        throw new IOException("No two-player game is declared by the content manifest");
    }

    static Selection load(Context context, String canonicalId) throws IOException {
        BuiltinGames.Entry entry = BuiltinGames.fromAssets(context).byCanonicalId(canonicalId);
        if (entry != null) {
            if (entry.multiplayerEligibility != BuiltinGames.MultiplayerEligibility.SUPPORTED ||
                    entry.multiplayerMaxPlayers != 2)
                throw new IOException("The peer game is not available locally");
            return read(context, entry);
        }
        if (!(context.getApplicationContext() instanceof FlyNesApplication))
            throw new IOException("The peer game is not available locally");
        var catalog = ((FlyNesApplication) context.getApplicationContext()).catalogRuntime();
        for (GameCatalogEntry candidate : catalog.gameCatalog().canonicalEntries()) {
            if (!candidate.canonicalGame().id().equals(canonicalId)) continue;
            for (GameVariant variant : candidate.variants()) {
                if (!variant.isLaunchable()) continue;
                try {
                    byte[] rom = catalog.nearbyContentLoader().load(variant.variantId()).bytes();
                    String title = GameTitlePresentation.forLocale(candidate.canonicalGame(),
                            context.getResources().getConfiguration().getLocales().get(0)).primary();
                    return new Selection(title, rom);
                } catch (Exception unavailable) {
                    throw new IOException("The peer game cannot be read locally", unavailable);
                }
            }
        }
        throw new IOException("The peer game is not available locally");
    }

    private static Selection read(Context context, BuiltinGames.Entry entry) throws IOException {
        try (InputStream input = context.getAssets().open(entry.assetPath());
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) {
                if (count > 0) output.write(buffer, 0, count);
                if (output.size() > 4 * 1024 * 1024) throw new IOException("MVP ROM is too large");
            }
            return new Selection(entry, output.toByteArray());
        }
    }

    private NearbyMvpGame() {}
}
