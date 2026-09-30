package com.flynes.emu;

import com.flynes.emu.app.FlyCatalogCommands;
import com.flynes.emu.app.NativeCatalogEntry;
import com.flynes.emu.catalog.BuiltinGames;
import com.flynes.emu.catalog.TestManifest;
import com.flynes.emu.catalog.android.*;
import com.flynes.emu.gamecenter.GameCenterSnapshotProjector;
import org.junit.Test;
import java.util.*;
import static org.junit.Assert.*;

public class ProductCatalogFactsTest {
    @Test public void sourceCountCountsCanonicalGamesAcrossPackagesAndVariants() throws Exception {
        var manifest=TestManifest.load();Map<String,String> backing=new HashMap<>();
        var uuids=new AndroidUuidSafMap(backing::get,backing::put,backing::remove);
        byte[] source=new byte[16];source[0]=3;uuids.put(source,"content://provider/tree/count");
        var state=NativeCatalogProjector.project(List.of(
                entry(source,FlyCatalogCommands.SOURCE_SCOPE_USER_DIRECTORY,"a".repeat(64),"one.nes","variant-one"),
                entry(source,FlyCatalogCommands.SOURCE_SCOPE_USER_DIRECTORY,"a".repeat(64),"copy.nes","variant-copy"),
                entry(source,FlyCatalogCommands.SOURCE_SCOPE_USER_DIRECTORY,"b".repeat(64),"other.nes","variant-other")),
                List.of(),Map.of(),0,uuids,new AndroidPackageLocatorMap(),(uri,path)->"content://provider/document/"+path,manifest,uri->true);
        var imported=state.sources().values().stream().filter(s->s.source().type()!=com.flynes.emu.catalog.RomSource.Type.BUILTIN).findFirst().orElseThrow();
        assertEquals(3,imported.packages().size());
        assertEquals(2,AndroidCatalogRuntime.productGameCount(imported));
    }
    @Test public void renamedUserDuplicateCannotRemoveBuiltinMultiplayerFacts() throws Exception {
        BuiltinGames manifest = TestManifest.load();
        var game = manifest.all().stream().filter(g -> g.multiplayerEligibility ==
                BuiltinGames.MultiplayerEligibility.SUPPORTED).findFirst().orElseThrow();
        Map<String,String> backing = new HashMap<>();
        var uuids = new AndroidUuidSafMap(backing::get, backing::put, backing::remove);
        byte[] builtin = new byte[16], imported = new byte[16];builtin[0]=1;imported[0]=2;
        uuids.put(imported,"content://provider/tree/imported");
        String canonical = "a".repeat(64);
        var state = NativeCatalogProjector.project(List.of(
                entry(builtin,FlyCatalogCommands.SOURCE_SCOPE_BUILTIN,canonical,game.assetFilename,"builtin-variant"),
                entry(imported,FlyCatalogCommands.SOURCE_SCOPE_USER_DIRECTORY,canonical,"AAA.nes","user-variant")),
                List.of(),Map.of(),0,uuids,new AndroidPackageLocatorMap(),
                (uri,path)->"content://provider/document/AAA",manifest,uri->true);
        var snapshot = new GameCenterSnapshotProjector().project(12,"b".repeat(64),1,state);
        assertEquals(1,snapshot.rows().size());
        assertEquals("AAA.nes",snapshot.rows().get(0).originalFilename());
        assertSame("Facts follow the builtin variant, never the aggregate display filename",
                game,ProductCatalogFacts.builtinMetadata(snapshot,manifest).get(canonical));
    }
    private static NativeCatalogEntry entry(byte[] uuid,int scope,String canonical,String path,String variant) {
        return new NativeCatalogEntry(uuid,16400,16400,16400,16384,0,0,0,0,
                new byte[20],new byte[32],new byte[32],new byte[4],scope,1,1,1,1,1,0,
                canonical,variant,path,path,new byte[0],-1);
    }
}
