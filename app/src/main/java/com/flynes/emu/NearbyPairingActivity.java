package com.flynes.emu;

import android.content.Context;
import android.content.Intent;
import android.Manifest;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.google.android.material.appbar.MaterialToolbar;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.WriterException;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;

import java.lang.ref.WeakReference;

/** One QR invitation page backed by the existing native host session. */
public final class NearbyPairingActivity extends AppCompatActivity {
    public static final String MODE_CREATE = "create";
    private static final String EXTRA_MODE = "nearby_mode";

    private NearbyMvpOwner mvpOwner;
    private NearbyMvpSession mvpSession;
    private boolean handoffStarted;
    private boolean hotspotStarting;
    private String shownMvpQr;
    private final Handler ticker = new Handler(Looper.getMainLooper());

    public static void start(@NonNull Context context, @NonNull String mode) {
        Intent intent = new Intent(context, NearbyPairingActivity.class);
        intent.putExtra(EXTRA_MODE, mode);
        context.startActivity(intent);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_nearby_pairing);
        MaterialToolbar toolbar = findViewById(R.id.nearby_pairing_toolbar);
        toolbar.setNavigationOnClickListener(view -> leavePage());
        View root = findViewById(R.id.nearby_pairing_root);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                    insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        root.requestApplyInsets();
        mvpOwner = ((FlyNesApplication) getApplication()).nearbyMvpOwner();
        findViewById(R.id.nearby_invite_regenerate).setOnClickListener(view -> startMvpHost());
        findViewById(R.id.nearby_invite_cancel).setOnClickListener(view -> disconnect());

        if (mvpOwner.active()) {
            mvpSession = mvpOwner.session();
            if (((FlyNesApplication) getApplication()).nearbyUiHotspot().active())
                showHotspotCredentials();
            else showNetworkStatus(R.string.nearby_network_lan_selected);
            renderMvpHost();
        } else {
            startMvpHost();
        }
        ticker.postDelayed(new Runnable() {
            @Override public void run() {
                if (isFinishing() || isDestroyed()) return;
                renderMvpHost();
                ticker.postDelayed(this, 250L);
            }
        }, 250L);
    }

    private void startMvpHost() {
        if (mvpOwner != null) mvpOwner.close();
        mvpSession = null;
        shownMvpQr = null;
        ((FrameLayout) findViewById(R.id.nearby_invite_qr)).removeAllViews();
        String lan = NearbyUiNetworkPath.connectedLan(this);
        if (lan != null) {
            // The invite must describe the network used by this host session.
            ((FlyNesApplication) getApplication()).nearbyUiHotspot().close();
            showNetworkStatus(R.string.nearby_network_lan_selected);
            startHostOn(lan);
            return;
        }
        if (((FlyNesApplication) getApplication()).nearbyUiHotspot().active()) {
            showHotspotCredentials();
            awaitHotspotAddress(0);
            return;
        }
        String existingHotspot = NearbyMvpLanAddress.current();
        if (existingHotspot != null) {
            showNetworkStatus(R.string.nearby_network_hotspot_selected);
            startHostOn(existingHotspot);
            return;
        }
        startAutomaticHotspot();
    }

    private void startHostOn(String ipv4) {
        try {
            if (mvpOwner == null || !mvpOwner.startHost(ipv4)) {
                status().setText(R.string.nearby_mvp_connection_failed);
                return;
            }
            mvpSession = mvpOwner.session();
            status().setText(R.string.nearby_screen_connecting);
        } catch (IllegalStateException failure) {
            status().setText(R.string.nearby_mvp_connection_failed);
        }
    }

    private void showNetworkStatus(int message) {
        TextView network = findViewById(R.id.nearby_network_status);
        network.setText(message);
        network.setVisibility(View.VISIBLE);
    }

    private void showHotspotCredentials() {
        NearbyUiHotspot hotspot = ((FlyNesApplication) getApplication()).nearbyUiHotspot();
        TextView network = findViewById(R.id.nearby_network_status);
        String ssid = hotspot.ssid();
        String password = hotspot.passphrase();
        network.setText(ssid == null || password == null
                ? getString(R.string.nearby_network_hotspot_selected)
                : getString(R.string.nearby_hotspot_credentials, ssid, password));
        network.setVisibility(View.VISIBLE);
    }

    private void startAutomaticHotspot() {
        if (hotspotStarting) return;
        if (Build.VERSION.SDK_INT < 26) {
            showNetworkStatus(R.string.nearby_hotspot_unavailable);
            status().setText(R.string.nearby_mvp_no_lan);
            return;
        }
        String permission = Build.VERSION.SDK_INT >= 33
                ? Manifest.permission.NEARBY_WIFI_DEVICES : Manifest.permission.ACCESS_FINE_LOCATION;
        if (ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, new String[]{permission}, 926);
            return;
        }
        WifiManager wifi = getSystemService(WifiManager.class);
        if (wifi == null) {
            showNetworkStatus(R.string.nearby_hotspot_unavailable);
            status().setText(R.string.nearby_mvp_no_lan);
            return;
        }
        hotspotStarting = true;
        showNetworkStatus(R.string.nearby_hotspot_starting);
        WeakReference<NearbyPairingActivity> page = new WeakReference<>(this);
        FlyNesApplication app = (FlyNesApplication) getApplication();
        try {
            wifi.startLocalOnlyHotspot(new WifiManager.LocalOnlyHotspotCallback() {
                @Override public void onStarted(WifiManager.LocalOnlyHotspotReservation reservation) {
                    app.nearbyUiHotspot().hold(reservation);
                    NearbyPairingActivity current = page.get();
                    if (current != null && !current.isDestroyed()) {
                        current.hotspotStarting = false;
                        current.showHotspotCredentials();
                        current.awaitHotspotAddress(0);
                    }
                }

                @Override public void onStopped() {
                    if (!app.nearbyUiHotspot().active()) return;
                    app.nearbyUiHotspot().close();
                    app.nearbyMvpOwner().close();
                    NearbyPairingActivity current = page.get();
                    if (current != null && !current.isDestroyed()) {
                        current.hotspotStarting = false;
                        ((FrameLayout) current.findViewById(R.id.nearby_invite_qr)).removeAllViews();
                        current.showNetworkStatus(R.string.nearby_hotspot_unavailable);
                        current.status().setText(R.string.nearby_mvp_no_lan);
                    }
                }

                @Override public void onFailed(int reason) {
                    NearbyPairingActivity current = page.get();
                    if (current != null && !current.isDestroyed()) {
                        current.hotspotStarting = false;
                        current.showNetworkStatus(R.string.nearby_hotspot_unavailable);
                        current.status().setText(R.string.nearby_mvp_no_lan);
                    }
                }
            }, new Handler(Looper.getMainLooper()));
        } catch (RuntimeException failure) {
            hotspotStarting = false;
            showNetworkStatus(R.string.nearby_hotspot_unavailable);
            status().setText(R.string.nearby_mvp_no_lan);
        }
    }

    private void awaitHotspotAddress(int attempt) {
        if (isFinishing() || isDestroyed()) return;
        String address = NearbyMvpLanAddress.current();
        if (address != null) {
            startHostOn(address);
        } else if (attempt < 32) {
            ticker.postDelayed(() -> awaitHotspotAddress(attempt + 1), 250L);
        } else {
            ((FlyNesApplication) getApplication()).nearbyUiHotspot().close();
            showNetworkStatus(R.string.nearby_hotspot_unavailable);
            status().setText(R.string.nearby_mvp_no_lan);
        }
    }

    @Override public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,
                                                      @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != 926) return;
        if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            startAutomaticHotspot();
        else {
            showNetworkStatus(R.string.nearby_hotspot_permission_denied);
            status().setText(R.string.nearby_mvp_no_lan);
        }
    }

    private TextView status() { return findViewById(R.id.nearby_invite_code_value); }

    private void renderMvpHost() {
        if (mvpSession == null) return;
        int[] snapshot = mvpSession.snapshot();
        if (snapshot == null || snapshot.length < 2) return;
        if (snapshot[0] == NearbyMvpSession.LOBBY) {
            ((FrameLayout) findViewById(R.id.nearby_invite_qr)).removeAllViews();
            shownMvpQr = null;
            status().setText(R.string.nearby_mvp_connected);
            if (!handoffStarted) {
                handoffStarted = true;
                ticker.postDelayed(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    startActivity(new Intent(this, NearbyLobbyActivity.class));
                    finish();
                }, 750L);
            }
            return;
        }
        if (snapshot[0] == NearbyMvpSession.ENDED) {
            ((FrameLayout) findViewById(R.id.nearby_invite_qr)).removeAllViews();
            shownMvpQr = null;
            status().setText(snapshot[1] == 4 ? R.string.nearby_mvp_expired
                    : R.string.nearby_mvp_connection_failed);
            disconnect();
            return;
        }
        String qr = mvpSession.invite();
        NearbyUiHotspot hotspot = ((FlyNesApplication) getApplication()).nearbyUiHotspot();
        if (hotspot.ssid() != null) {
            qr = NearbyNetworkInvite.withWifi(hotspot.ssid(), hotspot.passphrase(), qr);
        }
        if (qr == null || qr.equals(shownMvpQr)) return;
        try {
            BitMatrix matrix = new QRCodeWriter().encode(qr, BarcodeFormat.QR_CODE, 512, 512);
            Bitmap bitmap = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888);
            for (int y = 0; y < 512; y++) {
                for (int x = 0; x < 512; x++) {
                    bitmap.setPixel(x, y, matrix.get(x, y) ? 0xff000000 : 0xffffffff);
                }
            }
            ImageView image = new ImageView(this);
            image.setImageBitmap(bitmap);
            image.setContentDescription(getString(R.string.nearby_invite_qrLabel));
            image.setScaleType(ImageView.ScaleType.FIT_CENTER);
            FrameLayout frame = findViewById(R.id.nearby_invite_qr);
            frame.removeAllViews();
            frame.addView(image, new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
            shownMvpQr = qr;
            status().setText(R.string.nearby_mvp_waiting);
        } catch (WriterException error) {
            status().setText(R.string.nearby_mvp_connection_failed);
        }
    }

    private void leavePage() {
        startActivity(new Intent(this, HomeActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP));
        finish();
    }

    private void disconnect() {
        if (mvpOwner != null) mvpOwner.close();
        ((FlyNesApplication) getApplication()).nearbyUiHotspot().close();
        startActivity(new Intent(this, NearbyFriendsActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP));
        finish();
    }

    @Override public void onBackPressed() { leavePage(); }

    @Override protected void onDestroy() {
        ticker.removeCallbacksAndMessages(null);
        super.onDestroy();
    }
}
