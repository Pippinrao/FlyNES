package com.flynes.emu;

import static org.junit.Assert.assertEquals;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;

import org.junit.Test;

public final class NearbyQrDecoderTest {
    @Test public void decodesLuminanceFrameFromCameraPreview() throws Exception {
        String payload = "flynes-lan-v1:192.168.43.1:45321:"
                + "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:"
                + "0123456789abcdef0123456789abcdef";
        BitMatrix qr = new QRCodeWriter().encode(payload, BarcodeFormat.QR_CODE, 320, 320);
        byte[] nv21 = new byte[320 * 320 * 3 / 2];
        for (int y = 0; y < 320; y++) {
            for (int x = 0; x < 320; x++) {
                nv21[y * 320 + x] = (byte) (qr.get(x, y) ? 0 : 255);
            }
        }
        assertEquals(payload, NearbyQrDecoder.decodeNv21(nv21, 320, 320));
    }
}
