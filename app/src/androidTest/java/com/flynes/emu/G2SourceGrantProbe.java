package com.flynes.emu;

import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import org.json.JSONObject;
import java.util.concurrent.TimeUnit;

/** Explicit simulator evidence helper, not a product entry or a skipped test.
 * Only the G2-owned Download fixture can have its persisted read grant revoked.
 */
public final class G2SourceGrantProbe extends Instrumentation {
    private Bundle arguments;
    private static final Uri FIXTURE = Uri.parse("content://com.android.externalstorage.documents/tree/primary%3ADownload%2FG2-test-library");
    @Override public void onCreate(Bundle args) { arguments=args; start(); }
    @Override public void onStart() {
        Bundle result=new Bundle();
        try {
            if (!android.os.Build.FINGERPRINT.contains("generic") && !android.os.Build.FINGERPRINT.contains("emu64"))
                throw new IllegalStateException("Simulator only");
            waitForIdleSync();
            var context=getTargetContext();
            var app=(FlyNesApplication)context.getApplicationContext();
            app.catalogRuntime().nativeReady().get(30,TimeUnit.SECONDS);
            var prefs=context.getSharedPreferences("flynes_source_uuids",Context.MODE_PRIVATE);
            String uuid=prefs.getString("locator:"+FIXTURE,null);
            if(uuid==null)throw new IllegalStateException("Import owned G2 fixture through system picker first");
            long mappings=prefs.getAll().entrySet().stream().filter(e->!e.getKey().startsWith("locator:")&&FIXTURE.toString().equals(e.getValue())).count();
            if(mappings!=1)throw new AssertionError("Duplicate forward mappings: "+mappings);
            var rows=app.catalogRuntime().productSourcesSnapshot().stream().filter(r->uuid.equals(r.uuid())).toList();
            if(rows.size()!=1)throw new AssertionError("Duplicate/missing product source: "+rows.size());
            var resolver=context.getContentResolver();
            var otherBefore=resolver.getPersistedUriPermissions().stream().filter(p->!FIXTURE.equals(p.getUri())).map(p->p.getUri()+":"+p.isReadPermission()+":"+p.isWritePermission()).sorted().toList();
            String action=arguments.getString("action","audit");
            if("revoke".equals(action)) {
                if(!uuid.equals(arguments.getString("expectedUuid")))throw new AssertionError("Fixture identity changed");
                resolver.releasePersistableUriPermission(FIXTURE,Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } else if("reauthorize".equals(action)) {
                if(!uuid.equals(arguments.getString("expectedUuid")))throw new AssertionError("Fixture identity changed");
                app.catalogRuntime().addOrReauthorizeProductSource(FIXTURE.toString(),Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,uuid).get(30,TimeUnit.SECONDS);
            } else if(!"audit".equals(action))throw new IllegalArgumentException("audit, revoke or reauthorize only");
            boolean readable=resolver.getPersistedUriPermissions().stream().anyMatch(p->FIXTURE.equals(p.getUri())&&p.isReadPermission());
            if("revoke".equals(action)&&readable)throw new AssertionError("Read grant still present");
            var otherAfter=resolver.getPersistedUriPermissions().stream().filter(p->!FIXTURE.equals(p.getUri())).map(p->p.getUri()+":"+p.isReadPermission()+":"+p.isWritePermission()).sorted().toList();
            if(!otherBefore.equals(otherAfter))throw new AssertionError("Unrelated grant changed");
            result.putString("evidence",new JSONObject().put("action",action).put("uuid",uuid).put("forwardMappings",mappings).put("sourceRows",rows.size()).put("fixtureIndex",app.catalogRuntime().productSourcesSnapshot().indexOf(rows.get(0))).put("gameCount",rows.get(0).count()).put("readable",readable).put("unrelatedGrantsUnchanged",true).toString());
            finish(-1,result);
        }catch(Throwable failure){StringBuilder detail=new StringBuilder();
            for(Throwable cause=failure;cause!=null;cause=cause.getCause()) {
                detail.append(cause.getClass().getSimpleName()).append(": ").append(cause.getMessage()).append("\n");
                for(var frame:cause.getStackTrace())if(frame.getClassName().startsWith("com.flynes"))detail.append(frame).append("\n");
            }
            result.putString("failure",detail.toString());finish(1,result);}
    }
}
