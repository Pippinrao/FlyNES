package com.flynes.emu;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.qrcode.QRCodeWriter;
import org.junit.Test;
import java.util.Arrays;
import static org.junit.Assert.assertEquals;

public final class NearbyQrDecoderTest {
    @Test public void decodesLuminanceFrameFromCameraPreview() throws Exception {
        String payload = "flynes-lan-v1:192.168.43.1:45321:"
                + "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:"
                + "0123456789abcdef0123456789abcdef";
        var qr = new QRCodeWriter().encode(payload, BarcodeFormat.QR_CODE, 320, 320);
        byte[] nv21 = new byte[320 * 320 * 3 / 2];
        for (int y = 0; y < 320; y++) for (int x = 0; x < 320; x++)
            nv21[y * 320 + x] = (byte) (qr.get(x, y) ? 0 : 255);
        assertEquals(payload, NearbyQrDecoder.decodeNv21(nv21, 320, 320));
    }
    @Test public void denseRoomCodeIsFoundAtEverySamplingOffset() throws Exception {
        String invite = "flynes-lan-v1:192.168.3.3:45321:"
                + "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:"
                + "0123456789abcdef0123456789abcdef";
        var qr = new QRCodeWriter().encode(invite, BarcodeFormat.QR_CODE, 159, 159);
        NearbyQrDecoder decoder = new NearbyQrDecoder();
        for (int rotation = 0; rotation < 4; rotation++) {
            for (int offset = 0; offset < 11; offset++) {
                byte[] frame = new byte[2560 * 1440];
                Arrays.fill(frame, (byte) 220);
                for (int y = 0; y < qr.getHeight(); y++) for (int x = 0; x < qr.getWidth(); x++) {
                    int rx = x, ry = y;
                    for (int r = 0; r < rotation; r++) { int old = rx; rx = qr.getHeight() - 1 - ry; ry = old; }
                    frame[(350 + offset + ry) * 2560 + 1000 + rx] = (byte) (qr.get(x, y) ? 15 : 245);
                }
                assertEquals("rotation=" + rotation + " offset=" + offset, invite, decoder.decode(frame, 2560, 1440));
            }
        }
    }
}
