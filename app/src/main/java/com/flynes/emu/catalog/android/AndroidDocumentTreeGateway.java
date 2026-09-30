package com.flynes.emu.catalog.android;

import android.content.ContentResolver;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;

import com.flynes.emu.catalog.source.DocumentTreeGateway;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;

/** Read-only DocumentsContract adapter; it never requests provider write access. */
public final class AndroidDocumentTreeGateway implements DocumentTreeGateway {
    private static final String[] PROJECTION = {
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
    };

    private final ContentResolver resolver;
    private final Uri treeUri;
    private final android.os.CancellationSignal cancellation;

    public AndroidDocumentTreeGateway(ContentResolver resolver, String treeLocator) {
        this(resolver,treeLocator,null);
    }
    public AndroidDocumentTreeGateway(ContentResolver resolver, String treeLocator,
            android.os.CancellationSignal cancellation) {
        if (resolver == null || treeLocator == null) throw new NullPointerException();
        this.resolver = resolver;
        this.treeUri = Uri.parse(treeLocator);
        this.cancellation=cancellation;
    }
    private Cursor query(Uri uri) {
        try{return resolver.query(uri,PROJECTION,null,null,null,cancellation);}
        catch(android.os.OperationCanceledException cancelled){throw new java.util.concurrent.CancellationException();}
    }

    @Override
    public String rootDocumentId() throws IOException, SecurityException {
        if (!DocumentsContract.isTreeUri(treeUri)) {
            try (Cursor cursor=query(treeUri)) {
                if(cursor==null||!cursor.moveToFirst())throw new IOException("missing document");
                return "single-document-root:"+cursor.getString(0);
            }
        }
        final String expected;
        try { expected = DocumentsContract.getTreeDocumentId(treeUri); }
        catch (RuntimeException invalid) { throw new IOException("invalid tree URI", invalid); }
        if (expected == null || expected.length() == 0) throw new IOException("missing root ID");
        Uri root = DocumentsContract.buildDocumentUriUsingTree(treeUri, expected);
        try (Cursor cursor = query(root)) {
            if (cursor == null || !cursor.moveToFirst()) throw new IOException("missing root");
            String actual = cursor.getString(0);
            if (!expected.equals(actual) || cursor.moveToNext()) {
                throw new IOException("root identity mismatch");
            }
        }
        return expected;
    }

    @Override
    public ChildrenBatch listChildren(String parentDocumentId, int remainingNodeBudget)
            throws IOException, SecurityException {
        if (remainingNodeBudget < 0) throw new IllegalArgumentException("negative node budget");
        if(!DocumentsContract.isTreeUri(treeUri)) {
            if(remainingNodeBudget==0)return new ChildrenBatch(new ArrayList<>(),false);
            try(Cursor cursor=query(treeUri)) {
                if(cursor==null||!cursor.moveToFirst())throw new IOException("missing document");
                if(DocumentsContract.Document.MIME_TYPE_DIR.equals(cursor.getString(2)))throw new IOException("folder grant required");
                return new ChildrenBatch(java.util.Collections.singletonList(new DocumentNode(cursor.getString(0),cursor.getString(1),false,treeUri.toString())),true);
            }
        }
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri, parentDocumentId);
        ArrayList<DocumentNode> result = new ArrayList<>();
        try (Cursor cursor = query(children)) {
            if (cursor == null) throw new IOException("null children cursor");
            while (cursor.moveToNext()) {
                if(cancellation!=null&&cancellation.isCanceled())throw new java.util.concurrent.CancellationException();
                if (result.size() == remainingNodeBudget) {
                    return new ChildrenBatch(result, false);
                }
                String id = cursor.getString(0);
                String name = cursor.getString(1);
                String mime = cursor.getString(2);
                if (id == null || id.length() == 0 || name == null || name.length() == 0
                        || mime == null || mime.length() == 0) {
                    throw new IOException("incomplete document row");
                }
                Uri locator = DocumentsContract.buildDocumentUriUsingTree(treeUri, id);
                result.add(new DocumentNode(
                        id, name, DocumentsContract.Document.MIME_TYPE_DIR.equals(mime),
                        locator.toString()));
            }
        } catch (IllegalArgumentException malformed) {
            throw new IOException("invalid document tree", malformed);
        }
        return new ChildrenBatch(result, true);
    }

    @Override
    public InputStream open(String contentLocator) throws IOException, SecurityException {
        InputStream opened = resolver.openInputStream(Uri.parse(contentLocator));
        if (opened == null) throw new FileNotFoundException("provider returned null stream");
        return opened;
    }
}
