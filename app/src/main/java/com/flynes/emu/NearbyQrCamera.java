package com.flynes.emu;

import android.graphics.ImageFormat;
import android.hardware.Camera;
import android.os.SystemClock;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

import java.io.IOException;

/** QR camera source for a future scan surface; only valid Nearby payloads are consumed. */
@SuppressWarnings("deprecation")
public final class NearbyQrCamera implements SurfaceHolder.Callback, AutoCloseable {
    public interface Result { void onFound(String payload); }
    private final SurfaceView preview;
    private final Result result;
    private final Runnable onUnavailable;
    private Camera camera;
    private long lastDecodeMs;
    private boolean stopped;

    public NearbyQrCamera(SurfaceView preview, Result result, Runnable onUnavailable) {
        this.preview = preview;
        this.result = result;
        this.onUnavailable = onUnavailable;
    }

    public void start() {
        stopped = false;
        preview.getHolder().addCallback(this);
        if (preview.getHolder().getSurface().isValid()) surfaceCreated(preview.getHolder());
    }

    @Override public void surfaceCreated(SurfaceHolder holder) {
        if (stopped || camera != null) return;
        try {
            camera = Camera.open();
            Camera.Parameters parameters = camera.getParameters();
            parameters.setPreviewFormat(ImageFormat.NV21);
            Camera.Size chosen = null;
            for (Camera.Size size : parameters.getSupportedPreviewSizes()) {
                if (chosen == null || Math.abs(size.width - 640) + Math.abs(size.height - 480)
                        < Math.abs(chosen.width - 640) + Math.abs(chosen.height - 480)) chosen = size;
            }
            if (chosen != null) parameters.setPreviewSize(chosen.width, chosen.height);
            if (parameters.getSupportedFocusModes() != null &&
                    parameters.getSupportedFocusModes().contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE)) {
                parameters.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE);
            }
            camera.setParameters(parameters);
            Camera.CameraInfo info = new Camera.CameraInfo();
            Camera.getCameraInfo(0, info);
            int rotation = preview.getDisplay().getRotation();
            int degrees = rotation == Surface.ROTATION_90 ? 90 :
                    rotation == Surface.ROTATION_180 ? 180 :
                    rotation == Surface.ROTATION_270 ? 270 : 0;
            camera.setDisplayOrientation((info.orientation - degrees + 360) % 360);
            camera.setPreviewDisplay(holder);
            camera.setPreviewCallback((frame, device) -> decode(frame, device));
            camera.startPreview();
        } catch (RuntimeException | IOException error) {
            releaseCamera();
            onUnavailable.run();
        }
    }

    private void decode(byte[] frame, Camera device) {
        if (stopped || SystemClock.elapsedRealtime() - lastDecodeMs < 150) return;
        lastDecodeMs = SystemClock.elapsedRealtime();
        Camera.Size size = device.getParameters().getPreviewSize();
        String payload = NearbyQrDecoder.decodeNv21(frame, size.width, size.height);
        if (NearbyNetworkInvite.parse(payload) != null) {
            close();
            result.onFound(payload);
        }
    }

    @Override public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {}
    @Override public void surfaceDestroyed(SurfaceHolder holder) { releaseCamera(); }

    @Override public void close() {
        stopped = true;
        preview.getHolder().removeCallback(this);
        releaseCamera();
    }

    private void releaseCamera() {
        Camera old = camera;
        camera = null;
        if (old == null) return;
        try { old.setPreviewCallback(null); old.stopPreview(); } catch (RuntimeException ignored) {}
        old.release();
    }
}
