package com.flynes.emu.save;
import android.graphics.Bitmap;
import com.flynes.emu.NesCore;
import com.flynes.emu.video.FrameCopyResult;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
/** Captures a PNG from the same quiescent core position as the saved state. */
public final class HistoryThumbnail {
    private HistoryThumbnail() {}
    public static byte[] capture(NesCore core) {
        try {
            ByteBuffer pixels = ByteBuffer.allocateDirect(256 * 240 * 4);
            int[] info = new int[5];
            if (core.copyVideoFrameIfNew(pixels, info, -1).kind() != FrameCopyResult.Kind.NEW
                || info[3] != 0)
                return null;
            int w = info[0], h = info[1];
            byte[] packed = new byte[w * h * 2];
            for (int y = 0; y < h; y++) {
                pixels.position(y * info[2]);
                pixels.get(packed, y * w * 2, w * 2);
            }
            Bitmap bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.RGB_565);
            bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(packed));
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
            bitmap.recycle();
            return out.toByteArray();
        } catch (RuntimeException failure) {
            return null;
        }
    }
}
