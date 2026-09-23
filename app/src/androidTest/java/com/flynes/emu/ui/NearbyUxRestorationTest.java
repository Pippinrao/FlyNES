package com.flynes.emu.ui;

import android.content.Intent;
import android.view.View;
import android.widget.TextView;

import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import com.flynes.emu.NearbyFriendsActivity;
import com.flynes.emu.NearbyPairingActivity;
import com.flynes.emu.R;

import org.junit.Test;
import org.junit.runner.RunWith;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

/** Typography and target sizes for the approved single QR path. */
@RunWith(AndroidJUnit4.class)
public final class NearbyUxRestorationTest {
    @Test public void roleCardsPreserveReadableTypeAndTapTargets() {
        try (ActivityScenario<NearbyFriendsActivity> scenario =
                     ActivityScenario.launch(NearbyFriendsActivity.class)) {
            scenario.onActivity(activity -> {
                TextView title = activity.findViewById(R.id.nearby_entry_headline);
                View create = activity.findViewById(R.id.nearby_action_create);
                View scan = activity.findViewById(R.id.nearby_action_scan_qr);
                float density = activity.getResources().getDisplayMetrics().density;
                float scaled = activity.getResources().getDisplayMetrics().scaledDensity;
                assertEquals(21f, title.getTextSize() / scaled, 0.6f);
                assertTrue(create.getHeight() / density >= 48f);
                assertTrue(scan.getHeight() / density >= 48f);
            });
        }
    }

    @Test public void invitationStatusUsesBodyTypeBesideQr() {
        Intent intent = new Intent(ApplicationProvider.getApplicationContext(), NearbyPairingActivity.class)
                .putExtra("nearby_mode", NearbyPairingActivity.MODE_CREATE);
        try (ActivityScenario<NearbyPairingActivity> scenario = ActivityScenario.launch(intent)) {
            scenario.onActivity(activity -> {
                TextView status = activity.findViewById(R.id.nearby_invite_code_value);
                float scaled = activity.getResources().getDisplayMetrics().scaledDensity;
                assertEquals(14f, status.getTextSize() / scaled, 0.6f);
                assertTrue(activity.findViewById(R.id.nearby_invite_qr).isShown());
            });
            scenario.onActivity(activity -> activity.findViewById(R.id.nearby_invite_cancel).performClick());
        }
    }
}
