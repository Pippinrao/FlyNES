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

/** Opens the camera immediately and gives a valid invitation to the LAN join owner. */
@SuppressWarnings("deprecation")
public final class NearbyQrScannerActivity extends AppCompatActivity implements SurfaceHolder.Callback {
    private Camera camera;
    private TextView status;
    private View retry;
    private boolean scanned;
    private boolean decoding;
    private boolean joined;
    private long cameraStartedMs;
    private long recognizedMs;
    private long lastTimingLogMs;
    private int decodedFrames;
    private int cameraGeneration;
    private int previewWidth, previewHeight;
    private final NearbyQrDecoder decoder = new NearbyQrDecoder();
    private final java.util.concurrent.ExecutorService decodeWorker =
            java.util.concurrent.Executors.newSingleThreadExecutor();
    private NearbyScanJoinService joinService;
    private NearbyMvpOwner owner;
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_nearby_qr_scanner);
        owner = ((FlyNesApplication) getApplication()).nearbyMvpOwner();
        joinService = new NearbyScanJoinService(this, main, owner);
        View root = findViewById(R.id.nearby_scanner_root);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                    insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        root.requestApplyInsets();
        ((MaterialToolbar) findViewById(R.id.nearby_scanner_toolbar))
                .setNavigationOnClickListener(view -> finish());
        findViewById(R.id.nearby_scanner_cancel).setOnClickListener(view -> finish());
        status = findViewById(R.id.nearby_scanner_status);
        retry = findViewById(R.id.nearby_scanner_retry);
        retry.setOnClickListener(view -> {
            main.removeCallbacksAndMessages(null);
            joinService.close();
            scanned = false;
            findViewById(R.id.nearby_scanner_result).setVisibility(View.GONE);
            findViewById(R.id.nearby_scanner_preview).setVisibility(View.VISIBLE);
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
        if (holder.getSurface() == null || camera != null || scanned) return;
        try {
            camera = Camera.open();
            Camera.Parameters parameters = camera.getParameters();
            java.util.List<String> focusModes = parameters.getSupportedFocusModes();
            if (focusModes != null) {
                if (focusModes.contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE)) {
                    parameters.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE);
                } else if (focusModes.contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO)) {
                    parameters.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO);
                }
            }
            camera.setParameters(parameters);
            parameters = camera.getParameters();
            Camera.Size previewSize = parameters.getPreviewSize();
            previewWidth = previewSize.width;
            previewHeight = previewSize.height;
            cameraStartedMs = android.os.SystemClock.elapsedRealtime();
            decodedFrames = 0;
            trace("event=camera_open size=" + previewSize.width + "x" + previewSize.height
                    + " focus=" + parameters.getFocusMode());
            camera.setAutoFocusMoveCallback((moving, source) -> trace(
                    "event=focus moving=" + moving + " elapsed_ms=" + (android.os.SystemClock.elapsedRealtime() - cameraStartedMs)));
            ((NearbyCameraPreview) findViewById(R.id.nearby_scanner_preview))
                    .setPreviewSize(previewSize.width, previewSize.height);
            camera.setDisplayOrientation(0);
            camera.setPreviewDisplay(holder);
            camera.startPreview();
            camera.setOneShotPreviewCallback(this::decodeFrame);
        } catch (Exception failure) {
            closeCamera();
            status.setText(R.string.nearby_scanner_camera_unavailable);
            showResult(R.string.nearby_scanner_camera_unavailable);
            retry.setVisibility(View.VISIBLE);
        }
    }

    private void decodeFrame(byte[] data, Camera source) {
        if (scanned || decoding || camera != source || decodeWorker.isShutdown()) return;
        decoding = true;
        final int generation = cameraGeneration, width = previewWidth, height = previewHeight;
        decodeWorker.execute(() -> {
            long started = android.os.SystemClock.elapsedRealtime();
            String decoded = decoder.decode(data, width, height);
            long cost = android.os.SystemClock.elapsedRealtime() - started;
            int candidates = decoder.candidateCount();
            main.post(() -> {
                if (generation != cameraGeneration || camera != source || isFinishing()) return;
                decoding = false;
                decodedFrames++;
                long now = android.os.SystemClock.elapsedRealtime();
                if (decoded != null && !decoded.isEmpty()) {
                    trace("event=qr_decoded elapsed_ms=" + (now - cameraStartedMs) + " frames=" + decodedFrames
                            + " decode_ms=" + cost + " candidates=" + candidates);
                    acceptScannedText(decoded);
                    return;
                }
                if (now - lastTimingLogMs >= 1000) {
                    trace("event=decode_tick frames=" + decodedFrames + " decode_ms=" + cost
                            + " candidates=" + candidates);
                    lastTimingLogMs = now;
                }
                if (!scanned) camera.setOneShotPreviewCallback(this::decodeFrame);
            });
        });
    }

    void acceptScannedText(String text) {
        if (scanned || joined) return;
        scanned = true;
        recognizedMs = android.os.SystemClock.elapsedRealtime();
        closeCamera();
        showResult(R.string.nearby_scanner_recognized);
        status.setText(R.string.nearby_screen_connecting);
        if (NearbyNetworkInvite.parse(text) == null) {
            showJoinFailure(R.string.nearby_scanner_invalid);
            return;
        }
        boolean accepted = joinService.joinScannedText(text, this::pollConnection, () -> {
            if (!isFinishing() && !isDestroyed()) showJoinFailure();
        });
        if (!accepted) showJoinFailure();
    }

    private void showJoinFailure() {
        showJoinFailure(R.string.nearby_scanner_join_unavailable);
    }

    private void showJoinFailure(int message) {
        status.setText(message);
        retry.setVisibility(View.VISIBLE);
    }

    private void showResult(int message) {
        findViewById(R.id.nearby_scanner_preview).setVisibility(View.INVISIBLE);
        TextView result = findViewById(R.id.nearby_scanner_result);
        result.setText(message);
        result.setVisibility(View.VISIBLE);
    }

    private void pollConnection() {
        if (isFinishing() || isDestroyed() || joined) return;
        NearbyMvpSession session = owner.session();
        if (session == null) { showJoinFailure(); return; }
        int[] snapshot = session.snapshot();
        int state = snapshot[0];
        if (state == NearbyMvpSession.LOBBY || state == NearbyMvpSession.CONFIGURING
                || state == NearbyMvpSession.RUNNING) {
            joined = true;
            trace("event=room_connected join_ms=" +
                    (android.os.SystemClock.elapsedRealtime() - recognizedMs));
            startActivity(new Intent(this, NearbyLobbyActivity.class));
            finish();
        } else if (state == NearbyMvpSession.ENDED) {
            showJoinFailure(snapshot[1] == 4 ? R.string.nearby_mvp_expired
                    : R.string.nearby_scanner_join_unavailable);
        } else main.postDelayed(this::pollConnection, 100);
    }

    private void closeCamera() {
        cameraGeneration++;
        decoding = false;
        Camera closing = camera;
        camera = null;
        if (closing != null) {
            closing.setOneShotPreviewCallback(null);
            closing.stopPreview();
            closing.release();
        }
    }

    private void trace(String event) {
        android.util.Log.i("FlyNesScanner", event);
        if ((getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) return;
        // Some vendor devices suppress app logcat. Timing only; never store camera frames or invite text.
        try (java.io.FileWriter writer = new java.io.FileWriter(new java.io.File(getCacheDir(), "scanner-timing.log"), true)) {
            writer.write(android.os.SystemClock.elapsedRealtime() + " " + event + "\n");
        } catch (java.io.IOException ignored) { }
    }

    @Override protected void onPause() {
        closeCamera();
        super.onPause();
    }

    @Override protected void onDestroy() {
        decodeWorker.shutdownNow();
        main.removeCallbacksAndMessages(null);
        if (!joined && isFinishing() && joinService != null) joinService.close();
        super.onDestroy();
    }

    @Override protected void onResume() {
        super.onResume();
        SurfaceHolder holder = ((SurfaceView) findViewById(R.id.nearby_scanner_preview)).getHolder();
        if (holder.getSurface() != null && holder.getSurface().isValid()) openCamera(holder);
    }
}
