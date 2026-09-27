package com.flynes.emu;

import android.hardware.Camera;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.content.Intent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.appbar.MaterialToolbar;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.LuminanceSource;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.NotFoundException;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.common.HybridBinarizer;

/** Opens the camera immediately and gives a valid invitation to the LAN join owner. */
@SuppressWarnings("deprecation")
public final class NearbyQrScannerActivity extends AppCompatActivity implements SurfaceHolder.Callback {
    private Camera camera;
    private TextView status;
    private View retry;
    private boolean scanned;
    private boolean decoding;
    private boolean joined;
    private NearbyScanJoinService joinService;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_nearby_qr_scanner);
        joinService = new NearbyScanJoinService(this, new Handler(Looper.getMainLooper()),
                ((FlyNesApplication) getApplication()).nearbyMvpOwner());
        ((MaterialToolbar) findViewById(R.id.nearby_scanner_toolbar))
                .setNavigationOnClickListener(view -> finish());
        status = findViewById(R.id.nearby_scanner_status);
        retry = findViewById(R.id.nearby_scanner_retry);
        retry.setOnClickListener(view -> {
            scanned = false;
            retry.setVisibility(View.GONE);
            status.setText(R.string.nearby_scanner_prompt);
            if (camera == null) openCamera(((SurfaceView) findViewById(R.id.nearby_scanner_preview)).getHolder());
            else camera.setOneShotPreviewCallback(this::decodeFrame);
        });
        ((SurfaceView) findViewById(R.id.nearby_scanner_preview)).getHolder().addCallback(this);
    }

    @Override public void surfaceCreated(SurfaceHolder holder) { openCamera(holder); }
    @Override public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) { }
    @Override public void surfaceDestroyed(SurfaceHolder holder) { closeCamera(); }

    private void openCamera(SurfaceHolder holder) {
        if (holder.getSurface() == null || camera != null) return;
        try {
            camera = Camera.open();
            camera.setDisplayOrientation(0);
            camera.setPreviewDisplay(holder);
            camera.startPreview();
            camera.setOneShotPreviewCallback(this::decodeFrame);
        } catch (Exception failure) {
            closeCamera();
            status.setText(R.string.nearby_scanner_camera_unavailable);
            retry.setVisibility(View.VISIBLE);
        }
    }

    private void decodeFrame(byte[] data, Camera source) {
        if (scanned || decoding || camera == null) return;
        decoding = true;
        try {
            Camera.Size size = source.getParameters().getPreviewSize();
            LuminanceSource luminance = new PlanarYUVLuminanceSource(data, size.width, size.height,
                    0, 0, size.width, size.height, false);
            String decoded = new MultiFormatReader().decodeWithState(
                    new BinaryBitmap(new HybridBinarizer(luminance))).getText();
            if (decoded != null && !decoded.isEmpty()) {
                runOnUiThread(() -> acceptScannedText(decoded));
            }
        } catch (NotFoundException ignored) {
            // Most preview frames have no code; keep scanning.
        } catch (RuntimeException ignored) {
            // Camera previews can change size while a frame is being decoded.
        } finally {
            decoding = false;
            if (!scanned && camera != null) camera.setOneShotPreviewCallback(this::decodeFrame);
        }
    }

    void acceptScannedText(String text) {
        if (scanned || joined) return;
        scanned = true;
        status.setText(R.string.nearby_screen_connecting);
        boolean accepted = joinService.joinScannedText(text, () -> {
            if (isFinishing() || isDestroyed()) return;
            joined = true;
            startActivity(new Intent(this, NearbyLobbyActivity.class));
            finish();
        }, () -> {
            if (!isFinishing() && !isDestroyed()) showJoinFailure();
        });
        if (!accepted) showJoinFailure();
    }

    private void showJoinFailure() {
        status.setText(R.string.nearby_scanner_join_unavailable);
        retry.setVisibility(View.VISIBLE);
    }

    private void closeCamera() {
        Camera closing = camera;
        camera = null;
        if (closing != null) {
            closing.setOneShotPreviewCallback(null);
            closing.stopPreview();
            closing.release();
        }
    }

    @Override protected void onPause() {
        closeCamera();
        super.onPause();
    }

    @Override protected void onDestroy() {
        if (!joined && isFinishing() && joinService != null) joinService.close();
        super.onDestroy();
    }

    @Override protected void onResume() {
        super.onResume();
        SurfaceHolder holder = ((SurfaceView) findViewById(R.id.nearby_scanner_preview)).getHolder();
        if (holder.getSurface() != null && holder.getSurface().isValid()) openCamera(holder);
    }
}
