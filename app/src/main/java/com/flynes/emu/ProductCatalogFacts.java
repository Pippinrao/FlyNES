package com.flynes.emu;

import com.flynes.emu.catalog.BuiltinGames;
import com.flynes.emu.catalog.RomSource;
import com.flynes.emu.catalog.persistence.CatalogStateCodec;
import com.flynes.emu.gamecenter.GameCenterSnapshot;
import java.util.LinkedHashMap;
import java.util.Map;

/** Manifest facts for a captured product projection. */
final class ProductCatalogFacts {
    static Map<String,BuiltinGames.Entry> builtinMetadata(GameCenterSnapshot snapshot,BuiltinGames manifest) {
        Map<String,BuiltinGames.Entry> result = new LinkedHashMap<>();
        try {
            // These packages and rows were captured together. Display filenames aggregate all
            // variants and therefore cannot establish a game's manifest identity.
            var state = CatalogStateCodec.decode(snapshot.catalogStateBytes());
            for (var source : state.sources().values()) {
                if (source.source().type() != RomSource.Type.BUILTIN) continue;
                for (var stored : source.packages().values()) {
                    var physical = stored.physicalPackage();
                    var game = manifest.byAssetFilename(physical.originalFilename());
                    if (game == null) continue;
                    for (var variant : physical.variants()) result.put(variant.canonicalGame().id(),game);
                }
            }
        } catch (CatalogStateCodec.CodecException failure) {
            throw new IllegalStateException("snapshot_unavailable",failure);
        }
        return java.util.Collections.unmodifiableMap(result);
    }
}
