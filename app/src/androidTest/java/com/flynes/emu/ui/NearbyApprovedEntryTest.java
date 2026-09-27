package com.flynes.emu.ui;

import android.content.Intent;
import android.Manifest;
import android.app.Activity;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
import android.widget.HorizontalScrollView;
import android.widget.ScrollView;

import androidx.test.core.app.ActivityScenario;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.rule.GrantPermissionRule;
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry;
import androidx.test.runner.lifecycle.Stage;

import com.flynes.emu.NearbyFriendsActivity;
import com.flynes.emu.NearbyPairingActivity;
import com.flynes.emu.R;
import com.flynes.emu.SettingsActivity;
import com.flynes.emu.NearbyLobbyActivity;

import org.junit.Test;
import org.junit.Rule;
import org.junit.runner.RunWith;

import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

@RunWith(AndroidJUnit4.class)
public final class NearbyApprovedEntryTest {
    @Rule public GrantPermissionRule camera = GrantPermissionRule.grant(Manifest.permission.CAMERA);

    @Test public void settingsHasNoFriendsManagementEntry() {
        try (ActivityScenario<SettingsActivity> scenario = ActivityScenario.launch(SettingsActivity.class)) {
            scenario.onActivity(activity -> {
                int id = activity.getResources().getIdentifier("settings_nearby_friends_manage",
                        "id", activity.getPackageName());
                assertTrue(id == 0 || activity.findViewById(id) == null);
            });
        }
    }

    @Test public void lobbyKeepsGameAndActionTogetherWithoutDiagnostics() {
        try (ActivityScenario<NearbyLobbyActivity> scenario =
                     ActivityScenario.launch(NearbyLobbyActivity.class)) {
            scenario.onActivity(activity -> {
                View root = activity.findViewById(R.id.nearby_lobby_root);
                View game = activity.findViewById(R.id.nearby_lobby_row_rom_identity);
                int detailsId = activity.getResources().getIdentifier("nearby_lobby_details",
                        "id", activity.getPackageName());
                assertTrue(detailsId == 0 || activity.findViewById(detailsId) == null);
                assertTrue(inside(game, root));
                int[] gamePos = new int[2];
                game.getLocationOnScreen(gamePos);
                assertTrue("game choice stays in the right pane", gamePos[0] > root.getWidth() / 3);
                assertTrue(activity.getResources().getIdentifier("nearby_lobby_confirm", "id",
                        activity.getPackageName()) == 0);
                assertTrue(noScroll(root));
            });
        }
    }

    @Test public void scanActionOpensCameraWithoutPairingPage() {
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().getUiAutomation()
                .grantRuntimePermission("com.flynes.emu", android.Manifest.permission.CAMERA);
        try (ActivityScenario<NearbyFriendsActivity> scenario =
                     ActivityScenario.launch(NearbyFriendsActivity.class)) {
            scenario.onActivity(activity -> activity.findViewById(R.id.nearby_action_scan_qr)
                    .performClick());
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().waitForIdleSync();
            final String[] resumed = {""};
            long deadline = SystemClock.elapsedRealtime() + 3000;
            do {
                androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
                        .runOnMainSync(() -> {
                            for (Activity activity : ActivityLifecycleMonitorRegistry.getInstance()
                                    .getActivitiesInStage(Stage.RESUMED)) {
                                resumed[0] = activity.getClass().getSimpleName();
                            }
                        });
                if ("NearbyQrScannerActivity".equals(resumed[0])) break;
                SystemClock.sleep(20);
            } while (SystemClock.elapsedRealtime() < deadline);
            assertTrue("scan should enter camera directly; got " + resumed[0],
                    "NearbyQrScannerActivity".equals(resumed[0]));
        }
    }
    @Test public void entryShowsOnlyTwoFittingRolesWithoutScroll() {
        try (ActivityScenario<NearbyFriendsActivity> scenario =
                     ActivityScenario.launch(NearbyFriendsActivity.class)) {
            scenario.onActivity(activity -> {
                View root = activity.findViewById(R.id.nearby_root);
                View create = activity.findViewById(R.id.nearby_action_create);
                View scan = activity.findViewById(R.id.nearby_action_scan_qr);
                assertTrue(create.isShown());
                assertTrue(scan.isShown());
                assertTrue(inside(create, root));
                assertTrue(inside(scan, root));
                assertTrue(create.getHeight() >= dp(root, 48));
                assertTrue(scan.getHeight() >= dp(root, 48));
                assertTrue(absent(activity, "nearby_action_enter_code"));
                assertTrue(absent(activity, "nearby_tab_friends"));
                assertTrue(absent(activity, "nearby_find_devices"));
                assertTrue(noScroll(root));
            });
        }
    }

    @Test public void invitationUsesLargeSquareQrAndInlineActions() {
        Intent invite = new Intent(ApplicationProvider.getApplicationContext(),
                NearbyPairingActivity.class);
        invite.putExtra("nearby_mode", NearbyPairingActivity.MODE_CREATE);
        try (ActivityScenario<NearbyPairingActivity> scenario = ActivityScenario.launch(invite)) {
            scenario.onActivity(activity -> {
                View root = activity.findViewById(R.id.nearby_pairing_root);
                View qr = activity.findViewById(R.id.nearby_invite_qr);
                View regenerate = activity.findViewById(R.id.nearby_invite_regenerate);
                assertTrue(qr.getWidth() >= dp(root, 200));
                assertTrue(Math.abs(qr.getWidth() - qr.getHeight()) <= dp(root, 2));
                assertTrue(inside(qr, root));
                assertTrue(inside(regenerate, root));
                assertTrue(absent(activity, "nearby_pairing_footer"));
                assertTrue("pairing-code controls must be removed", absent(activity, "nearby_join_block"));
                assertTrue("legacy scan explanation must be removed", absent(activity, "nearby_scan_block"));
                assertTrue(noScroll(root));
            });
            scenario.onActivity(activity -> activity.finish());
        }
    }

    private static int dp(View view, int value) {
        return Math.round(value * view.getResources().getDisplayMetrics().density);
    }

    private static boolean absent(NearbyFriendsActivity activity, String idName) {
        int id = activity.getResources().getIdentifier(idName, "id", activity.getPackageName());
        return id == 0 || activity.findViewById(id) == null;
    }

    private static boolean absent(NearbyPairingActivity activity, String idName) {
        int id = activity.getResources().getIdentifier(idName, "id", activity.getPackageName());
        return id == 0 || activity.findViewById(id) == null;
    }

    private static boolean inside(View child, View root) {
        int[] a = new int[2], b = new int[2];
        child.getLocationOnScreen(a);
        root.getLocationOnScreen(b);
        return a[0] >= b[0] && a[1] >= b[1]
                && a[0] + child.getWidth() <= b[0] + root.getWidth()
                && a[1] + child.getHeight() <= b[1] + root.getHeight();
    }

    private static boolean noScroll(View view) {
        if (view instanceof ScrollView || view instanceof HorizontalScrollView) return false;
        if (!(view instanceof ViewGroup)) return true;
        ViewGroup group = (ViewGroup) view;
        for (int i = 0; i < group.getChildCount(); i++) {
            if (!noScroll(group.getChildAt(i))) return false;
        }
        return true;
    }
}
