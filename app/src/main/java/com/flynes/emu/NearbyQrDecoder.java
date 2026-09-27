package com.flynes.emu;

import com.google.zxing.BinaryBitmap;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.NotFoundException;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.common.HybridBinarizer;

/** Decodes the Y plane without retaining camera frames or invitation data. */
final class NearbyQrDecoder {
    private final MultiFormatReader reader = new MultiFormatReader();
    private int candidateCount;
    NearbyQrDecoder() {
        java.util.Map<com.google.zxing.DecodeHintType, Object> hints =
                new java.util.EnumMap<>(com.google.zxing.DecodeHintType.class);
        hints.put(com.google.zxing.DecodeHintType.POSSIBLE_FORMATS,
                java.util.Collections.singletonList(com.google.zxing.BarcodeFormat.QR_CODE));
        hints.put(com.google.zxing.DecodeHintType.TRY_HARDER, Boolean.TRUE);
        hints.put(com.google.zxing.DecodeHintType.NEED_RESULT_POINT_CALLBACK,
                (com.google.zxing.ResultPointCallback) point -> candidateCount++);
        reader.setHints(hints);
    }
    int candidateCount() { return candidateCount; }
    static String decodeNv21(byte[] frame, int width, int height) {
        return new NearbyQrDecoder().decode(frame, width, height);
    }
    String decode(byte[] data, int width, int height) {
        candidateCount = 0;
        if (data == null || width <= 0 || height <= 0 || width > 4096 || height > 4096
                || data.length < width * height) return null;
        try {
            return reader.decodeWithState(new BinaryBitmap(new HybridBinarizer(
                    new PlanarYUVLuminanceSource(data, width, height, 0, 0, width, height, false)))).getText();
        } catch (NotFoundException | IllegalArgumentException missing) { return null; }
        finally { reader.reset(); }
    }
}
