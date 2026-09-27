package com.flynes.emu;

import android.graphics.Bitmap;
import android.graphics.drawable.BitmapDrawable;
import android.os.SystemClock;
import android.widget.FrameLayout;
import android.widget.ImageView;
import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.RGBLuminanceSource;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.qrcode.QRCodeReader;
import java.lang.reflect.Field;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import static org.junit.Assert.*;

public final class NearbyHotspotInviteTest {
    @Test public void lanRegenerationDoesNotAdvertisePreviousHotspotCredentials() throws Exception {
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        assertNotNull(NearbyUiNetworkPath.connectedLan(app));
        app.nearbyMvpOwner().close();
        NearbyUiHotspot hotspot = app.nearbyUiHotspot();
        hotspot.close();
        try {
            set(hotspot, "ssid", "Previous test hotspot");
            set(hotspot, "passphrase", "test-only-pass");
            try (ActivityScenario<NearbyPairingActivity> page = ActivityScenario.launch(NearbyPairingActivity.class)) {
                NearbyNetworkInvite decoded = NearbyNetworkInvite.parse(readQr(page));
                assertNotNull(decoded);
                assertFalse("A router LAN invitation must not direct guests to an old hotspot", decoded.hasWifi());
            }
        } finally {
            app.nearbyMvpOwner().close();
            hotspot.close();
        }
    }

    @Test public void displayedHotspotQrCarriesWifiAndCurrentNativeInvite() throws Exception {
        FlyNesApplication app = ApplicationProvider.getApplicationContext();
        NearbyUiHotspot hotspot = app.nearbyUiHotspot();
        app.nearbyMvpOwner().close();
        hotspot.close();
        try {
            assertTrue(app.nearbyMvpOwner().startHost(NearbyMvpLanAddress.current()));
            // Emulators have no AP radio. Inject only the system-supplied metadata;
            // native invitation, product rendering and QR decoding remain real.
            set(hotspot, "ssid", "FlyNES test hotspot");
            set(hotspot, "passphrase", "test-only-pass");
            try (ActivityScenario<NearbyPairingActivity> page =
                         ActivityScenario.launch(NearbyPairingActivity.class)) {
                NearbyNetworkInvite decoded = NearbyNetworkInvite.parse(readQr(page));
                assertNotNull(decoded);
                assertTrue("The displayed QR must request hotspot association before joining", decoded.hasWifi());
                assertEquals("FlyNES test hotspot", decoded.ssid());
                assertEquals("test-only-pass", decoded.passphrase());
                assertEquals(app.nearbyMvpOwner().session().invite(), decoded.lanInvite());
            }
        } finally {
            app.nearbyMvpOwner().close();
            hotspot.close();
        }
    }

    private static void set(Object target, String name, String value) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        field.set(target, value);
    }

    private static String readQr(ActivityScenario<NearbyPairingActivity> page) throws Exception {
        AtomicReference<Bitmap> image = new AtomicReference<>();
        long deadline = SystemClock.elapsedRealtime() + 8000;
        while (SystemClock.elapsedRealtime() < deadline) {
            page.onActivity(activity -> {
                FrameLayout frame = activity.findViewById(R.id.nearby_invite_qr);
                if (frame.getChildCount() == 1 && frame.getChildAt(0) instanceof ImageView)
                    image.set(((BitmapDrawable) ((ImageView) frame.getChildAt(0)).getDrawable()).getBitmap());
            });
            Bitmap bitmap = image.get();
            if (bitmap != null) {
                int[] pixels = new int[bitmap.getWidth() * bitmap.getHeight()];
                bitmap.getPixels(pixels, 0, bitmap.getWidth(), 0, 0, bitmap.getWidth(), bitmap.getHeight());
                return new QRCodeReader().decode(new BinaryBitmap(new HybridBinarizer(
                        new RGBLuminanceSource(bitmap.getWidth(), bitmap.getHeight(), pixels))),
                        java.util.Collections.singletonMap(com.google.zxing.DecodeHintType.PURE_BARCODE, true)).getText();
            }
            SystemClock.sleep(50);
        }
        throw new AssertionError("Product did not render an invitation QR");
    }
}
