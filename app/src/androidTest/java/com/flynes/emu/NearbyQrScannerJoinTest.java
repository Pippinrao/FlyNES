package com.flynes.emu;

import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

@RunWith(AndroidJUnit4.class)
public final class NearbyQrScannerJoinTest {
    @Test public void invalidCodeStopsCameraAndOffersRetryOnSamePage() {
        try (ActivityScenario<NearbyQrScannerActivity> scenario =
                     ActivityScenario.launch(NearbyQrScannerActivity.class)) {
            scenario.onActivity(activity -> {
                activity.acceptScannedText("not a room invitation");
                assertTrue("stop camera presentation after recognition",
                        activity.findViewById(R.id.nearby_scanner_preview).getVisibility()
                                != android.view.View.VISIBLE);
                assertTrue(activity.findViewById(R.id.nearby_scanner_retry).isShown());
                assertTrue(!activity.isFinishing());
            });
        }
    }

    @Test public void scannedInviteStartsRealGuestSessionAndOpensLobby() {
        FlyNesApplication app = (FlyNesApplication) ApplicationProvider.getApplicationContext();
        app.nearbyMvpOwner().close();
        NearbyMvpSession host = new NearbyMvpSession();
        try {
            String address = NearbyMvpLanAddress.current();
            assertTrue(address != null && host.host(address));
            String invite = awaitInvite(host);
            try (ActivityScenario<NearbyQrScannerActivity> scenario =
                         ActivityScenario.launch(NearbyQrScannerActivity.class)) {
                scenario.onActivity(activity -> activity.acceptScannedText(invite));
                long deadline = android.os.SystemClock.elapsedRealtime() + 5_000;
                int hostState = 0, guestState = 0;
                while (android.os.SystemClock.elapsedRealtime() < deadline) {
                    hostState = host.snapshot()[0];
                    NearbyMvpSession guest = app.nearbyMvpOwner().session();
                    if (guest != null) guestState = guest.snapshot()[0];
                    if (hostState == NearbyMvpSession.LOBBY && guestState == NearbyMvpSession.LOBBY)
                        break;
                    android.os.SystemClock.sleep(10);
                }
                assertEquals(NearbyMvpSession.LOBBY, guestState);
                assertEquals(2, app.nearbyMvpOwner().session().snapshot()[4]);
            }
        } finally {
            app.nearbyMvpOwner().close();
            host.close();
        }
    }

    private static String awaitInvite(NearbyMvpSession host) {
        long deadline = android.os.SystemClock.elapsedRealtime() + 5_000;
        while (android.os.SystemClock.elapsedRealtime() < deadline) {
            String value = host.invite();
            if (value != null) return value;
            android.os.SystemClock.sleep(10);
        }
        throw new AssertionError("host did not publish an invitation");
    }
}
