package com.flynes.emu;

import com.google.zxing.BinaryBitmap;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.ReaderException;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.qrcode.QRCodeReader;

/** Decodes only the luminance plane of a camera NV21 preview frame. */
final class NearbyQrDecoder {
    static String decodeNv21(byte[] frame, int width, int height) {
        if (frame == null || width <= 0 || height <= 0 || width > 4096 || height > 4096
                || frame.length < width * height) return null;
        try {
            PlanarYUVLuminanceSource source = new PlanarYUVLuminanceSource(
                    frame, width, height, 0, 0, width, height, false);
            return new QRCodeReader().decode(new BinaryBitmap(new HybridBinarizer(source))).getText();
        } catch (ReaderException | IllegalArgumentException error) {
            return null;
        }
    }
}
