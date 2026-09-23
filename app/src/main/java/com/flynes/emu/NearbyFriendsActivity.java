package com.flynes.emu;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.content.Intent;
import android.view.View;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;

import com.google.android.material.appbar.MaterialToolbar;

/** One nearby entry with a host and a guest action on every platform. */
public final class NearbyFriendsActivity extends AppCompatActivity
        implements PermissionGate.CameraPermissionHost {

    private boolean cameraDeniedOnce;
    private PermissionGate.Outcome pendingCameraOutcome;

    @Override public void requestCamera(PermissionGate.Outcome outcome) {
        pendingCameraOutcome = outcome;
        ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.CAMERA},
                PermissionGate.REQUEST_CAMERA);
    }

    @Override public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,
                                                     @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != PermissionGate.REQUEST_CAMERA || pendingCameraOutcome == null) return;
        boolean denied = grantResults.length == 0
                || grantResults[0] != PackageManager.PERMISSION_GRANTED;
        PermissionGate.Outcome outcome = pendingCameraOutcome;
        pendingCameraOutcome = null;
        outcome.onDone(denied);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_nearby_friends);

        MaterialToolbar toolbar = findViewById(R.id.nearby_toolbar);
        toolbar.setNavigationOnClickListener(view -> finish());

        View root = findViewById(R.id.nearby_root);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(insets.getSystemWindowInsetLeft(),
                    insets.getSystemWindowInsetTop(),
                    insets.getSystemWindowInsetRight(),
                    insets.getSystemWindowInsetBottom());
            return insets;
        });
        root.requestApplyInsets();

        findViewById(R.id.nearby_action_create).setOnClickListener(view ->
                NearbyPairingActivity.start(this, NearbyPairingActivity.MODE_CREATE));
        findViewById(R.id.nearby_action_scan_qr).setOnClickListener(view -> onScanClicked());
    }

    private void onScanClicked() {
        if (PermissionGate.hasCamera(this)) {
            startActivity(new Intent(this, NearbyQrScannerActivity.class));
            return;
        }
        if (cameraDeniedOnce) {
            showScanDeniedReason();
            return;
        }
        cameraDeniedOnce = true;
        PermissionGate.requestCamera(this, denied -> {
            if (denied) showScanDeniedReason();
            else startActivity(new Intent(this, NearbyQrScannerActivity.class));
        });
    }

    private void showScanDeniedReason() {
        TextView reason = findViewById(R.id.nearby_scan_denied_reason);
        reason.setText(R.string.nearby_reason_permission_cameraDenied);
        reason.setVisibility(View.VISIBLE);
    }
}
